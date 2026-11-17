import java.nio.file.Files
import java.nio.file.Path

/*
 * The samples.txt file read by the PlotTrellis app, written at the top of the output folder.
 *
 * One row per condition (the samplesheet's 'condition', or the group name when it is empty) and
 * one 'type:name' column per track. The app compares conditions on columns of the same name, so
 * every group of an assay gives the same column names; ChIP/CUT&RUN/CUT&Tag tracks are named
 * after the samplesheet's 'target'. Paths are relative to the output folder ('# data_root: .').
 */
class AppSamples {

    static final Map<String, String> DEFAULT_LABEL = [rna: 'RNA', atac: 'ATAC', chip: 'ChIP', cutrun: 'CUT&RUN', cuttag: 'CUT&Tag', hic: 'HiC']
    static final Map<String, String> ORGDB = [human: 'org.Hs.eg.db', mouse: 'org.Mm.eg.db']
    static final Map<String, String> GENOME_LABEL = [human: 'hg38', mouse: 'mm39']

    // The app tracks of a group: [type, name, path], with path relative to the output folder.
    // 'check' is the file that must exist (a quantdir is a folder holding quant.sf)
    static List<Map> tracks(Map g) {
        String a = g.assay
        String n = g.group
        if (a == 'rna') {
            return [
                [type: 'bw', name: 'RNA', path: "rna/coverage/${n}.bw"],
                [type: 'paired-end', name: 'junctions', path: "rna/junctions/${n}.junctions.bed"],
                [type: 'quantdir', name: 'salmon', path: "rna/quantification_mean/${n}", check: "rna/quantification_mean/${n}/quant.sf"]
            ].collect { t -> t.collectEntries { k, v -> [k, v.toString()] } }
        }
        if (a == 'hic') return [[type: 'hic', name: 'HiC', path: "hic/contacts/${n}.hic".toString()]]
        List<Map> out = [[type: 'bw', name: g.label, path: "${a}/coverage/${n}.bw".toString()]]
        if (!g.is_control) out << [type: 'bed', name: "${g.label}_peaks".toString(), path: "${a}/peaks/${n}_peaks.${g.peak_type}Peak".toString()]
        return out
    }

    // The samples.txt text for the groups whose files are in the output folder, or null if there are none
    static String build(List<Map> groups, Path outdir, Map info) {
        List<String> assays = Samplesheet.ASSAYS
        List<String> columns = []
        List<String> conditions = []
        Map<String, Map<String, String>> cells = [:]
        groups.withIndex().sort(false) { x, y -> assays.indexOf(x[0].assay) <=> assays.indexOf(y[0].assay) ?: x[1] <=> y[1] }.each { gi ->
            Map g = gi[0]
            tracks(g).each { t ->
                if (!Files.exists(outdir.resolve(t.check ?: t.path))) return
                String column = "${t.type}:${t.name}".toString()
                if (!(column in columns)) columns << column
                cells.computeIfAbsent(g.condition) { [:] }[column] = t.path
            }
        }
        // Conditions in samplesheet order
        groups.each { g -> if (cells.containsKey(g.condition) && !(g.condition in conditions)) conditions << g.condition }
        if (!conditions) return null

        List<String> lines = [
            "# PlotTrellis app samples file, written by PlotTrellis-wf ${info.version} on ${info.date}.".toString(),
            '# Paths are relative to the folder of this file.',
            '# data_root: .'
        ]
        if (info.gtf && Files.exists(outdir.resolve(info.gtf))) lines << "# gtf_path: ${info.gtf}".toString()
        lines << "# orgdb: ${ORGDB[info.species]}".toString()
        lines << "# genome_label: ${GENOME_LABEL[info.species]}".toString()
        lines << (['condition', 'colour'] + columns).join('\t')
        conditions.each { c -> lines << ([c, ''] + columns.collect { col -> cells[c][col] ?: '' }).join('\t') }
        return lines.join('\n') + '\n'
    }
}
