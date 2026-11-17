/*
 * GENCODE references, blacklists and genome constants for human (GRCh38) and mouse (GRCm39).
 */
class GenomeRefs {

    static final Map<String, String> GENCODE_BASE = [
        human: 'https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human',
        mouse: 'https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_mouse'
    ]

    static final Map<String, String> ASSEMBLY = [human: 'GRCh38', mouse: 'GRCm39']

    // Default blacklists shipped in assets/blacklists (from dozmorovlab/excluderanges; see the README there)
    static final Map<String, String> BLACKLIST_FILE = [
        human: 'assets/blacklists/hg38.Kundaje.GRCh38_unified_Excludable.bed',
        mouse: 'assets/blacklists/mm39.excluderanges.bed'
    ]

    // deepTools effective genome sizes (number of non-N bases). deepTools recommends these
    // when multimapping reads are kept, which is the case in this pipeline.
    // https://deeptools.readthedocs.io/en/latest/content/feature/effectiveGenomeSize.html
    static final Map<String, Long> EFFECTIVE_GENOME_SIZE = [human: 3130250755L, mouse: 2654621783L]

    // Regular expression matching autosomes (chr1-chr22 for human, chr1-chr19 for mouse)
    static final Map<String, String> AUTOSOME_REGEX = [
        human: 'chr([1-9]|1[0-9]|2[0-2])',
        mouse: 'chr([1-9]|1[0-9])'
    ]

    // Turns the --gencode value into a release name: '50' for human, 'M39' for mouse
    static String resolveRelease(String species, Object requested) {
        String req = requested == null || requested == true ? 'latest' : requested.toString().trim()
        if (!req || req.equalsIgnoreCase('latest')) return latestRelease(species)

        req = req.replaceFirst(/^[vV]/, '')
        if (species == 'human') {
            if (!(req ==~ /\d+/)) throw new IllegalArgumentException("--gencode '${requested}' is not a human GENCODE release. Use a number such as 50, or 'latest'.")
            return req
        }
        if (req.toUpperCase().startsWith('M')) req = req.substring(1)
        if (!(req ==~ /\d+/)) throw new IllegalArgumentException("--gencode '${requested}' is not a mouse GENCODE release. Use a release such as M39, or 'latest'.")
        if ((req as int) < 26) throw new IllegalArgumentException("--gencode M${req} uses the old GRCm38 mouse assembly. This pipeline uses GRCm39, available from GENCODE M26 onwards.")
        return "M${req}".toString()
    }

    // resolveRelease() for main.nf: [release: ..., error: null], or [release: null, error: message].
    // main.nf can't catch the exception itself: a try/catch in the workflow body stops Nextflow
    // before 25.04 from compiling main.nf, and then from reporting the Nextflow version it needs
    static Map resolveReleaseOrError(String species, Object requested) {
        try {
            return [release: resolveRelease(species, requested), error: null]
        } catch (IllegalArgumentException e) {
            return [release: null, error: e.message]
        }
    }

    static String latestRelease(String species) {
        String html
        try {
            html = URI.create(GENCODE_BASE[species] + '/').toURL().getText(connectTimeout: 30000, readTimeout: 60000)
        } catch (Exception e) {
            throw new IllegalArgumentException("could not reach the GENCODE website to find the latest release (${e.message}). Specify a release with --gencode.")
        }
        def pattern = species == 'human' ? /release_(\d+)\// : /release_M(\d+)\//
        List<Integer> releases = (html =~ pattern).collect { (it[1] as String) as int }
        if (!releases) throw new IllegalArgumentException('could not find any GENCODE release on the GENCODE website. Specify a release with --gencode.')
        int latest = releases.max()
        return species == 'human' ? "${latest}".toString() : "M${latest}".toString()
    }

    static Map<String, String> urls(String species, String release) {
        String dir = "${GENCODE_BASE[species]}/release_${release}"
        return [
            genome     : "${dir}/${ASSEMBLY[species]}.primary_assembly.genome.fa.gz".toString(),
            gtf        : "${dir}/gencode.v${release}.primary_assembly.annotation.gtf.gz".toString(),
            transcripts: "${dir}/gencode.v${release}.transcripts.fa.gz".toString()
        ]
    }

    // Returns true if the URL answers with HTTP 200 (used to give an early, clear error)
    static boolean exists(String url) {
        try {
            HttpURLConnection conn = (HttpURLConnection) URI.create(url).toURL().openConnection()
            conn.setRequestMethod('HEAD')
            conn.setConnectTimeout(30000)
            conn.setReadTimeout(60000)
            conn.setInstanceFollowRedirects(true)
            return conn.getResponseCode() == 200
        } catch (Exception e) {
            return false
        }
    }

    // --blacklist: false (default) -> 'off'; true -> 'default' (excluderanges); a path -> 'custom'
    static String blacklistMode(Object value) {
        if (value == null || value == false) return 'off'
        String v = value.toString().trim()
        if (!v || v.equalsIgnoreCase('false')) return 'off'
        if (v.equalsIgnoreCase('true')) return 'default'
        return 'custom'
    }
}
