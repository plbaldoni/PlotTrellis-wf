/*
 * On/off options. With Nextflow's v2 syntax parser, values given on the command line arrive as text,
 * so '--hic-dedup false' is the string 'false' (which Groovy treats as true). These helpers read
 * true/false the same way under both parsers.
 */
class Flags {

    static boolean isTrue(Object value) {
        if (value instanceof Boolean) return value
        return value != null && value.toString().trim().toLowerCase() in ['true', 'yes', 'on']
    }

    static boolean isFalse(Object value) {
        if (value instanceof Boolean) return !value
        return value == null || value.toString().trim().toLowerCase() in ['', 'false', 'no', 'off']
    }

    // An option that is on unless it is explicitly off
    static boolean on(Object value) {
        return !isFalse(value)
    }
}
