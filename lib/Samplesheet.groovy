import groovy.xml.XmlSlurper

import java.nio.file.Files
import java.nio.file.Paths
import java.util.zip.ZipFile

/*
 * Reads and validates the PlotTrellis samplesheet (.xlsx or .csv).
 *
 * All problems are collected and reported together, in plain English, so that
 * users can fix their spreadsheet in one go before anything is submitted to SLURM.
 */
class Samplesheet {

    static final List<String> REQUIRED_COLUMNS = ['sample', 'group', 'biological_replicate', 'technical_replicate', 'assay', 'fastq_1', 'fastq_2', 'control']
    static final List<String> OPTIONAL_COLUMNS = ['peak_type', 'gsm', 'condition', 'target']
    static final List<String> ASSAYS = ['rna', 'atac', 'chip', 'cutrun', 'cuttag', 'hic']
    static final List<String> DNA_ASSAYS = ['atac', 'chip', 'cutrun', 'cuttag']   // coverage and peaks
    static final List<String> CONTROL_ASSAYS = ['chip', 'cutrun', 'cuttag']
    static final Map<String, String> ASSAY_NAMES = [rna: 'RNA-seq', atac: 'ATAC-seq', chip: 'ChIP-seq', cutrun: 'CUT&RUN', cuttag: 'CUT&Tag', hic: 'Hi-C']
    static final List<String> PEAK_TYPES = ['narrow', 'broad']
    static final String SAFE_NAME = /^[A-Za-z0-9._-]+$/
    static final String GSM_PATTERN = /^GSM\d+$/
    static final String APP_NAME = /^[A-Za-z0-9 ._&+()-]+$/   // condition and target names shown in the app

    /*
     * Rows with the same sample name are technical replicates of that sample; their FASTQ
     * files are merged by the pipeline.
     *
     * A row with empty FASTQ columns and a GEO sample accession in the optional 'gsm' column is
     * downloaded: its SRA runs are looked up at NCBI and become the sample's technical replicates.
     *
     * Returns a map with:
     *   samples  - list of [meta: Map, app: Map, runs: List<Map>] for the selected assays, with one run
     *              per technical replicate: [technical_replicate, name, reads: List<String>, sra: Map]
     *              (reads are the FASTQ paths of local files; sra is [gsm, run, single_end] for downloads)
     *   errors   - list of problems (pipeline must stop if not empty)
     *   warnings - list of non-fatal notes
     *   app_groups - every group of the samplesheet (all assays, whatever --assay selects), as
     *              [assay, group, condition, label, is_control, peak_type], for the app's samples.txt
     */
    static Map load(String path, Object assaySelection, String defaultPeakType, String species) {
        List<String> errors = []
        List<String> warnings = []

        if (!Files.exists(Paths.get(path))) {
            return [samples: [], errors: ["The samplesheet '${path}' does not exist.".toString()], warnings: warnings]
        }

        List<List> table
        try {
            table = readTable(path)
        } catch (Exception e) {
            return [samples: [], errors: ["Could not read the samplesheet '${path}': ${e.message}".toString()], warnings: warnings]
        }
        if (table.size() < 2) {
            return [samples: [], errors: ['The samplesheet is empty: it needs a header row and at least one sample row.'], warnings: warnings]
        }

        // Header (case is ignored, and spaces or '-' count as '_', e.g. 'Biological replicate')
        List<String> header = (table[0][1] as List<String>).collect { (it ?: '').trim().toLowerCase().replaceAll(/[\s-]+/, '_') }
        List<String> missing = REQUIRED_COLUMNS.findAll { !(it in header) }
        if (missing) {
            errors << "The samplesheet is missing these required column(s): ${missing.join(', ')}. The header row must contain: ${REQUIRED_COLUMNS.join(', ')}.".toString()
            return [samples: [], errors: errors, warnings: warnings]
        }

        // Rows
        List<Map> rows = []
        table.drop(1).each { entry ->
            int rowNum = entry[0] as int
            List<String> values = entry[1] as List<String>
            if (values.every { !(it?.trim()) }) return // skip blank rows
            Map row = [row: rowNum]
            header.eachWithIndex { col, i ->
                if (col) row[col] = (i < values.size() ? (values[i] ?: '') : '').trim()
            }
            rows << row
        }
        if (!rows) {
            return [samples: [], errors: ['The samplesheet has a header row but no samples.'], warnings: warnings]
        }

        // Per-row checks
        rows.each { r ->
            String where = "Row ${r.row}" + (r.sample ? " (sample '${r.sample}')" : '')
            r.assay = r.assay.toLowerCase()
            r.peak_type = (r.peak_type ?: '').toLowerCase()

            if (!r.sample) errors << "${where}: the 'sample' column is empty."
            else if (!(r.sample ==~ SAFE_NAME)) errors << "${where}: sample names may only contain letters, numbers, '.', '_' and '-' (no spaces)."

            if (!r.group) errors << "${where}: the 'group' column is empty."
            else if (!(r.group ==~ SAFE_NAME)) errors << "${where}: group names may only contain letters, numbers, '.', '_' and '-' (no spaces)."

            if (!r.biological_replicate) errors << "${where}: the 'biological_replicate' column is empty."
            if (r.technical_replicate && !(r.technical_replicate ==~ SAFE_NAME)) errors << "${where}: 'technical_replicate' may only contain letters, numbers, '.', '_' and '-' (no spaces)."

            if (!r.assay) errors << "${where}: the 'assay' column is empty. Use one of: ${ASSAYS.join(', ')}."
            else if (!(r.assay in ASSAYS)) errors << "${where}: unknown assay '${r.assay}'. Use one of: ${ASSAYS.join(', ')}."

            // A GEO sample accession is used only when both FASTQ columns are empty
            String gsmGiven = r.gsm ?: ''
            r.gsm = gsmGiven.toUpperCase()
            r.download = !r.fastq_1 && !r.fastq_2 && r.gsm as boolean
            if (r.download) {
                if (!(r.gsm ==~ GSM_PATTERN)) errors << "${where}: '${gsmGiven}' in the 'gsm' column is not a GEO sample accession (GSM followed by numbers, e.g. GSM7142991)."
            } else {
                if (!r.fastq_1 && !r.fastq_2 && 'gsm' in header) errors << "${where}: the 'fastq_1' and 'gsm' columns are both empty. Give the FASTQ file paths, or a GEO sample accession (GSM...) to download the data."
                else checkFastq(r.fastq_1, 'fastq_1', where, true, errors)
                checkFastq(r.fastq_2, 'fastq_2', where, false, errors)
                if (r.fastq_1 && r.fastq_1 == r.fastq_2) errors << "${where}: 'fastq_1' and 'fastq_2' point to the same file."
            }

            if (r.peak_type && !(r.peak_type in PEAK_TYPES)) errors << "${where}: 'peak_type' must be empty, 'narrow' or 'broad' (found '${r.peak_type}')."
            if (r.peak_type && r.assay in ['rna', 'hic']) warnings << "${where}: 'peak_type' is ignored for ${ASSAY_NAMES[r.assay]} samples."
            if (r.assay == 'hic' && r.fastq_1 && !r.fastq_2) errors << "${where}: Hi-C samples must be paired-end. Fill in 'fastq_2'."

            // Names used in the PlotTrellis app: the condition (one row of the app) and, for ChIP/CUT&RUN/CUT&Tag, the target (track name)
            r.condition = r.condition ?: ''
            r.target = r.target ?: ''
            if (r.condition && !(r.condition ==~ APP_NAME)) errors << "${where}: 'condition' may only contain letters, numbers, spaces and . _ - & + ( ) (found '${r.condition}')."
            if (r.target && r.assay in ASSAYS && !(r.assay in CONTROL_ASSAYS)) {
                warnings << "${where}: 'target' is ignored for ${ASSAY_NAMES[r.assay]} samples."
                r.target = ''
            }
            if (r.target && !(r.target ==~ APP_NAME)) errors << "${where}: 'target' may only contain letters, numbers, spaces and . _ - & + ( ) (found '${r.target}')."

            r.controls = (r.control ?: '').split(/[;,]/)*.trim().findAll { it }
            if (r.controls && r.assay in ASSAYS && !(r.assay in CONTROL_ASSAYS)) errors << "${where}: ${ASSAY_NAMES[r.assay]} samples cannot have a control. Leave the 'control' column empty."
            if (r.sample && r.sample in r.controls) errors << "${where}: a sample cannot be its own control."
        }

        // Cross-row checks
        Map<String, Integer> fastqRow = [:]
        rows.each { r ->
            [r.fastq_1, r.fastq_2].findAll { it }.unique().each { f ->
                if (fastqRow.containsKey(f)) errors << "Rows ${fastqRow[f]} and ${r.row}: the FASTQ file ${f} is used more than once.".toString()
                else fastqRow[f] = r.row
            }
        }

        Map<String, Integer> gsmRow = [:]
        rows.findAll { it.download }.each { r ->
            if (gsmRow.containsKey(r.gsm)) errors << "Rows ${gsmRow[r.gsm]} and ${r.row}: the GEO sample ${r.gsm} is used more than once.".toString()
            else gsmRow[r.gsm] = r.row
        }

        // Rows with the same sample name are technical replicates of that sample
        Map<String, List<Map>> bySample = rows.findAll { it.sample }.groupBy { it.sample }
        bySample.each { name, reps ->
            if (reps.size() == 1) return
            String where = "Sample '${name}' (rows ${reps*.row.join(', ')})"
            if (reps.any { it.download }) {
                errors << "${where}: a sample downloaded from GEO must be on a single row. All sequencing runs of the GSM are found and merged automatically.".toString()
                return
            }
            List<String> numbers = reps*.technical_replicate
            if (numbers.any { !it }) errors << "${where}: this sample name is used on ${reps.size()} rows. Rows with the same sample name are technical replicates and are merged, so number them in the 'technical_replicate' column (1, 2, ...). If they are different samples, give them different names.".toString()
            else if (numbers.unique(false).size() < numbers.size()) errors << "${where}: each technical replicate of a sample needs a different 'technical_replicate' number (found ${numbers.join(', ')}).".toString()
            ['group', 'biological_replicate', 'assay', 'peak_type', 'condition', 'target'].each { col ->
                List<String> found = reps.collect { it[col] ?: '(empty)' }.unique()
                if (found.size() > 1) errors << "${where}: technical replicates of a sample must have the same '${col}' (found ${found.join(', ')}).".toString()
            }
            if (reps.collect { it.controls.sort(false) }.unique().size() > 1) errors << "${where}: technical replicates of a sample must have the same 'control'.".toString()
            if (reps.collect { !it.fastq_2 }.unique().size() > 1) errors << "${where}: mixes single-end and paired-end technical replicates.".toString()
            if (reps.collectMany { [it.fastq_1, it.fastq_2] }.findAll { it }.collect { it.endsWith('.gz') }.unique().size() > 1) errors << "${where}: mixes compressed (.gz) and uncompressed FASTQ files. Technical replicates are merged by joining their files, so they must be all compressed or all uncompressed.".toString()
        }

        // SRA runs of the GEO samples to download (each run becomes a technical replicate)
        List<Map> downloads = rows.findAll { it.download && it.gsm ==~ GSM_PATTERN }
        if (downloads) {
            Map<String, Map> found = GeoSamples.lookup(downloads*.gsm.unique())
            downloads.each { r ->
                String where = "Row ${r.row} (sample '${r.sample}', ${r.gsm})"
                Map hit = found[r.gsm]
                if (hit.error) {
                    errors << "${where}: ${r.gsm} ${hit.error}".toString()
                    return
                }
                r.sra_runs = hit.runs
                if (hit.runs*.single_end.unique().size() > 1) errors << "${where}: ${r.gsm} has both single-end and paired-end runs (${hit.runs.collect { "${it.run} ${it.single_end ? 'single' : 'paired'}" }.join(', ')}). Download them yourself and list them as FASTQ files.".toString()
                r.sra_single_end = hit.runs[0].single_end
                if (r.assay == 'hic' && r.sra_single_end) errors << "${where}: Hi-C samples must be paired-end, but ${r.gsm} is single-end.".toString()
                List<String> organisms = hit.runs.findAll { it.taxid != GeoSamples.TAXON_ID[species] }*.organism.unique()
                if (species in GeoSamples.TAXON_ID && organisms) errors << "${where}: ${r.gsm} is ${organisms.join(', ')} data, but --species is ${species}.".toString()
                List<String> platforms = hit.runs*.platform.findAll { it && !it.equalsIgnoreCase('ILLUMINA') }.unique()
                if (platforms) warnings << "${where}: ${r.gsm} was sequenced on ${platforms.join(', ')}. This pipeline is designed for Illumina short reads.".toString()
            }
        }

        Set<String> controlNames = rows.collectMany { it.controls } as Set
        rows.each { r ->
            String where = "Row ${r.row} (sample '${r.sample}')"
            r.controls.each { c ->
                Map ctrl = bySample[c]?.getAt(0)
                if (!ctrl) errors << "${where}: the control '${c}' is not a sample in this samplesheet."
                else {
                    if (ctrl.assay != r.assay) errors << "${where}: the control '${c}' is a '${ctrl.assay}' sample but this sample is '${r.assay}'. A control must have the same assay."
                    if (ctrl.controls) errors << "${where}: the control '${c}' has a control of its own. Controls (e.g. input or IgG) must leave the 'control' column empty."
                }
            }
            r.is_control = r.sample in controlNames
            r.single_end = r.download ? r.sra_single_end : !r.fastq_2
        }

        // Group checks (groups are defined within an assay)
        rows.findAll { it.group && it.assay }.groupBy { "${it.assay}__${it.group}".toString() }.each { key, members ->
            String label = "Group '${members[0].group}' (assay '${members[0].assay}')"
            if (members*.single_end.unique().size() > 1) errors << "${label}: mixes single-end and paired-end samples. All samples in a group must be the same."
            if (members*.is_control.unique().size() > 1) errors << "${label}: mixes control samples (input/IgG) with non-control samples. Put controls in their own group."
            List<String> types = members.findAll { !it.is_control }.collect { it.peak_type ?: defaultPeakType }.unique()
            if (types.size() > 1) errors << "${label}: samples have different 'peak_type' values (${types.join(', ')}). Peaks are called per group, so all samples in a group must use the same peak type."
            ['condition', 'target'].each { col ->
                List<String> found = members.collect { it[col] ?: '(empty)' }.unique()
                if (found.size() > 1) errors << "${label}: samples have different '${col}' values (${found.join(', ')}). All samples in a group must have the same ${col}.".toString()
            }
            members.findAll { it.biological_replicate }.groupBy { it.biological_replicate }.each { rep, reps ->
                List<String> names = reps*.sample.unique()
                if (names.size() > 1) errors << "${label}: samples ${names.join(', ')} have the same biological_replicate (${rep}). If they are technical replicates of one sample, give them the same sample name and number them in the 'technical_replicate' column."
            }
        }

        // Groups as rows and tracks of the app's samples.txt: two groups in one condition cannot have a track of the same name
        List<Map> appGroups = rows.findAll { it.group && it.assay in ASSAYS }.groupBy { "${it.assay}__${it.group}".toString() }.collect { key, members ->
            Map r = members[0]
            [assay: r.assay, group: r.group, condition: r.condition ?: r.group, label: r.target ?: AppSamples.DEFAULT_LABEL[r.assay],
             is_control: r.is_control, peak_type: r.is_control || r.assay in ['rna', 'hic'] ? '' : (r.peak_type ?: defaultPeakType)]
        }
        appGroups.groupBy { it.condition }.each { condition, groups ->
            Map<String, Map> owner = [:]
            Map<List, List<String>> clashes = [:]
            groups.each { g ->
                AppSamples.tracks(g).each { t ->
                    String column = "${t.type}:${t.name}".toString()
                    if (owner[column]) clashes.computeIfAbsent([owner[column], g]) { [] } << column
                    else owner[column] = g
                }
            }
            clashes.each { pair, columns ->
                Map a = pair[0], b = pair[1]
                String fix = a.assay in CONTROL_ASSAYS || b.assay in CONTROL_ASSAYS ? "'target' or 'condition'" : "'condition'"
                errors << "Condition '${condition}': groups '${a.group}' (${a.assay}) and '${b.group}' (${b.assay}) would give the same app track${columns.size() > 1 ? 's' : ''} ${columns.collect { "'${it}'" }.join(', ')}. Give one of them a different ${fix}.".toString()
            }
        }

        // Assay selection
        List<String> present = rows*.assay.findAll { it in ASSAYS }.unique()
        List<String> selected = parseAssays(assaySelection, present, errors)

        if (errors) return [samples: [], errors: errors.collect { it.toString() }, warnings: warnings.collect { it.toString() }]

        List<Map> samples = rows.findAll { it.assay in selected }.groupBy { it.sample }.collect { name, reps ->
            Map r = reps[0]
            [
                meta: [
                    id                  : r.sample,
                    group               : r.group,
                    biological_replicate: r.biological_replicate,
                    assay               : r.assay,
                    single_end          : r.single_end,
                    is_control          : r.is_control,
                    controls            : r.controls,
                    peak_type           : r.is_control || r.assay in ['rna', 'hic'] ? '' : (r.peak_type ?: defaultPeakType)
                ],
                // Used only for the app's samples.txt, so kept out of meta: changing them does not rerun any task
                app: [condition: r.condition, target: r.target],
                // FastQC runs on each technical replicate; 'name' labels its reports
                runs: r.download ?
                    r.sra_runs.withIndex().collect { run, i ->
                        [
                            technical_replicate: "${i + 1}".toString(),
                            name               : r.sra_runs.size() > 1 ? "${name}_T${i + 1}".toString() : name,
                            reads              : [],
                            sra                : [gsm: r.gsm, run: run.run, single_end: run.single_end]
                        ]
                    } :
                    reps.collect { t ->
                        [
                            technical_replicate: t.technical_replicate,
                            name               : reps.size() > 1 ? "${name}_T${t.technical_replicate}".toString() : name,
                            reads              : t.single_end ? [t.fastq_1] : [t.fastq_1, t.fastq_2],
                            sra                : null
                        ]
                    }
            ]
        }
        if (!samples) errors << "No samples in the samplesheet match the selected assay(s): ${selected.join(', ')}.".toString()

        // Group size and the group's controls, so that each group is processed as soon as its own samples are ready
        samples.groupBy { "${it.meta.assay}__${it.meta.group}".toString() }.each { key, members ->
            List<String> groupControls = members.collectMany { it.meta.controls }.unique().sort()
            members.each { it.meta.group_size = members.size(); it.meta.group_controls = groupControls }
        }

        return [samples: samples, errors: errors.collect { it.toString() }, warnings: warnings.collect { it.toString() }, app_groups: appGroups]
    }

    // Summarises a list of sample metas from the same group into one group meta
    static Map groupMeta(List<Map> metas) {
        Map m = metas[0]
        return [
            key       : "${m.assay}__${m.group}".toString(),
            group     : m.group,
            assay     : m.assay,
            single_end: m.single_end,
            is_control: m.is_control,
            peak_type : m.peak_type,
            controls  : m.group_controls,
            samples   : metas*.id.sort()
        ]
    }

    // Writes the validated samplesheet as CSV (for the record), one row per technical replicate.
    // For downloaded runs, fastq_1/fastq_2 are where the files are kept (empty if they are not kept).
    static String toCsv(List<Map> samples, String fastqDir) {
        List<String> lines = ['sample,group,biological_replicate,technical_replicate,assay,fastq_1,fastq_2,control,peak_type,condition,target,gsm,sra_run,single_end,is_control']
        samples.each { s ->
            Map m = s.meta
            s.runs.each { run ->
                List<String> reads = run.sra ?
                    (fastqDir ? (1..(run.sra.single_end ? 1 : 2)).collect { i -> "${fastqDir}/${run.sra.run}_R${i}.fastq.gz".toString() } : []) :
                    run.reads
                lines << [m.id, m.group, m.biological_replicate, run.technical_replicate, m.assay, reads[0] ?: '', reads.size() > 1 ? reads[1] : '',
                          m.controls.join(';'), m.peak_type, csvField(s.app.condition), csvField(s.app.target), run.sra?.gsm ?: '', run.sra?.run ?: '', m.single_end, m.is_control].join(',')
            }
        }
        return lines.join('\n') + '\n'
    }

    private static String csvField(String value) {
        return value && (value.contains(',') || value.contains('"')) ? '"' + value.replace('"', '""') + '"' : (value ?: '')
    }

    private static List<String> parseAssays(Object selection, List<String> present, List<String> errors) {
        String sel = selection == null || selection == true ? 'all' : selection.toString().trim().toLowerCase()
        if (!sel || sel == 'all') return present
        List<String> wanted = sel.split(/[,\s]+/)*.trim().findAll { it }
        List<String> unknown = wanted.findAll { !(it in ASSAYS) }
        if (unknown) errors << "--assay: unknown assay(s) ${unknown.join(', ')}. Use one or more of: ${ASSAYS.join(', ')} (comma-separated), or 'all'.".toString()
        return wanted.findAll { it in ASSAYS }
    }

    private static void checkFastq(String value, String column, String where, boolean required, List<String> errors) {
        if (!value) {
            if (required) errors << "${where}: the '${column}' column is empty.".toString()
            return
        }
        if (!value.startsWith('/')) {
            errors << "${where}: '${column}' must be a full (absolute) path starting with '/' (found '${value}').".toString()
            return
        }
        if (!Files.exists(Paths.get(value))) {
            errors << "${where}: the file in '${column}' does not exist: ${value}".toString()
        }
    }

    // ---------------------------------------------------------------------
    // Table readers. Each returns a list of [rowNumber, List<String> values].
    // ---------------------------------------------------------------------

    static List<List> readTable(String path) {
        String lower = path.toLowerCase()
        if (lower.endsWith('.xlsx')) return readXlsx(path)
        if (lower.endsWith('.csv')) return readCsv(path)
        throw new IllegalArgumentException('the samplesheet must be an Excel .xlsx file (or a .csv file)')
    }

    static List<List> readCsv(String path) {
        List<List> rows = []
        Paths.get(path).toFile().readLines('UTF-8').eachWithIndex { line, i ->
            rows << [i + 1, parseCsvLine(line.replaceFirst(/^﻿/, ''))]
        }
        return rows
    }

    static List<String> parseCsvLine(String line) {
        List<String> out = []
        StringBuilder sb = new StringBuilder()
        boolean quoted = false
        for (int i = 0; i < line.length(); i++) {
            char ch = line.charAt(i)
            if (quoted) {
                if (ch == '"' as char) {
                    if (i + 1 < line.length() && line.charAt(i + 1) == '"' as char) { sb.append('"'); i++ }
                    else quoted = false
                } else sb.append(ch)
            } else {
                if (ch == '"' as char) quoted = true
                else if (ch == ',' as char) { out << sb.toString(); sb.setLength(0) }
                else sb.append(ch)
            }
        }
        out << sb.toString()
        return out
    }

    // Minimal .xlsx reader: first worksheet, cell values as text (no formulas evaluated)
    static List<List> readXlsx(String path) {
        ZipFile zip = new ZipFile(path)
        try {
            Closure slurp = { String name ->
                def entry = zip.getEntry(name)
                entry ? new XmlSlurper(false, false).parse(zip.getInputStream(entry)) : null
            }

            List<String> shared = []
            def sst = slurp('xl/sharedStrings.xml')
            if (sst != null) {
                sst.si.each { si -> shared << textOf(si) }
            }

            def workbook = slurp('xl/workbook.xml')
            def rels = slurp('xl/_rels/workbook.xml.rels')
            if (workbook == null || rels == null) throw new IllegalArgumentException('this does not look like a valid .xlsx file')
            String rid = workbook.sheets.sheet[0].@'r:id'.text()
            String target = rels.Relationship.find { it.@Id.text() == rid }.@Target.text()
            String sheetPath = target.startsWith('/') ? target.substring(1) : (target.startsWith('xl/') ? target : 'xl/' + target)
            def sheet = slurp(sheetPath)
            if (sheet == null) throw new IllegalArgumentException("could not find the first worksheet (${sheetPath})")

            List<List> rows = []
            sheet.sheetData.row.each { row ->
                int rowNum = row.@r.text() ? (row.@r.text() as int) : rows.size() + 1
                List<String> values = []
                row.c.each { c ->
                    String ref = c.@r.text()
                    int col = ref ? columnIndex(ref) : values.size()
                    String type = c.@t.text()
                    String v
                    if (type == 's') v = shared[c.v.text() as int]
                    else if (type == 'inlineStr') v = textOf(c.is)
                    else v = c.v.text()
                    while (values.size() <= col) values << ''
                    values[col] = v ?: ''
                }
                rows << [rowNum, values]
            }
            return rows
        } finally {
            zip.close()
        }
    }

    // Concatenates <t> text runs, skipping phonetic hints (<rPh>)
    private static String textOf(node) {
        StringBuilder sb = new StringBuilder()
        node.'**'.findAll { it.name() == 't' && it.parent().name() != 'rPh' }.each { sb.append(it.text()) }
        return sb.toString()
    }

    private static int columnIndex(String ref) {
        int n = 0
        for (char ch : ref.toUpperCase().toCharArray()) {
            if (ch < ('A' as char) || ch > ('Z' as char)) break
            n = n * 26 + (ch - ('A' as char) + 1)
        }
        return n - 1
    }
}
