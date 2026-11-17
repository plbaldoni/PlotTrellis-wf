import groovy.json.JsonSlurper

/*
 * Finds the SRA sequencing runs of GEO samples (GSM accessions) with NCBI E-utilities:
 * esearch (db=sra, term=GSM) gives the SRA entries of the sample, and efetch (rettype=runinfo)
 * their runs, read layout, platform and organism. Only runs whose SRA sample name (or library
 * name) is the GSM itself are kept.
 *
 * NCBI allows 3 requests per second without an API key, and 10 with one (read from the
 * NCBI_API_KEY environment variable).
 */
class GeoSamples {

    static final String EUTILS = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils'
    static final Map<String, String> TAXON_ID = [human: '9606', mouse: '10090']

    /*
     * Returns a map from each GSM to either
     *   [runs: List<Map>]  one map per run, sorted by run accession:
     *                      [run, single_end, platform, taxid, organism, spots]
     *   [error: String]    why the runs could not be found
     */
    static Map<String, Map> lookup(Collection<String> gsms) {
        String apiKey = System.getenv('NCBI_API_KEY') ?: ''
        long pause = apiKey ? 120L : 400L
        Map<String, Map> result = [:]
        gsms.each { gsm ->
            try {
                def search = new JsonSlurper().parseText(get("${EUTILS}/esearch.fcgi?db=sra&term=${gsm}&retmax=1000&retmode=json", apiKey))
                List ids = search?.esearchresult?.idlist ?: []
                sleep(pause)
                if (!ids) {
                    result[gsm] = [error: 'was not found in SRA (check the accession; the data may not be public yet, or may not have been deposited in SRA)']
                    return
                }
                String csv = get("${EUTILS}/efetch.fcgi?db=sra&id=${ids.join(',')}&rettype=runinfo&retmode=text", apiKey)
                sleep(pause)
                List<Map> runs = parseRunInfo(csv).findAll { r ->
                    r.SampleName?.equalsIgnoreCase(gsm) || r.LibraryName?.equalsIgnoreCase(gsm)
                }.collect { r ->
                    [
                        run       : r.Run,
                        single_end: r.LibraryLayout?.toUpperCase() != 'PAIRED',
                        platform  : r.Platform ?: '',
                        taxid     : r.TaxID ?: '',
                        organism  : r.ScientificName ?: '',
                        spots     : r.spots ?: ''
                    ]
                }.unique { it.run }.sort { a, b -> compareRuns(a.run, b.run) }
                result[gsm] = runs ? [runs: runs] : [error: 'has no sequencing runs in SRA (the data may not be public yet, or may not have been deposited in SRA)']
            } catch (Exception e) {
                result[gsm] = [error: "could not be looked up at NCBI (${e.message}). Check the internet connection, or try again later."]
            }
        }
        return result
    }

    // runinfo is CSV with a header line (repeated between batches)
    private static List<Map> parseRunInfo(String csv) {
        List<String> lines = csv.readLines().findAll { it.trim() }
        if (!lines) return []
        List<String> header = Samplesheet.parseCsvLine(lines[0])
        return lines.drop(1).findAll { !it.startsWith('Run,') }.collect { line ->
            List<String> values = Samplesheet.parseCsvLine(line)
            Map row = [:]
            header.eachWithIndex { col, i -> row[col] = i < values.size() ? values[i].trim() : '' }
            row
        }.findAll { it.Run }
    }

    // SRR9 before SRR10: compare the prefix, then the number
    private static int compareRuns(String x, String y) {
        def mx = x =~ /^([A-Za-z]+)(\d+)$/
        def my = y =~ /^([A-Za-z]+)(\d+)$/
        if (!mx.matches() || !my.matches()) return x <=> y
        return (mx.group(1) <=> my.group(1)) ?: ((mx.group(2) as long) <=> (my.group(2) as long))
    }

    // GET with a few retries (NCBI answers 429 when requests come too fast, and the network can fail briefly)
    private static String get(String url, String apiKey) {
        String full = url + '&tool=PlotTrellis-wf' + (apiKey ? "&api_key=${apiKey}" : '')
        Exception last = null
        for (int attempt = 1; attempt <= 4; attempt++) {
            try {
                return URI.create(full).toURL().getText(connectTimeout: 30000, readTimeout: 120000)
            } catch (Exception e) {
                last = e
                sleep(3000L * attempt)
            }
        }
        throw last
    }
}
