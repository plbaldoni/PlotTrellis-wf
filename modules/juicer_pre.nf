process juicer_pre {
  // .hic contact map per group with juicer_tools pre defaults (all of its resolutions, no MAPQ filter).
  // -k adds KR to the normalisations that Juicer Tools 2 computes by default (VC, VC_SQRT, SCALE).
  // The wrapper script's Java heap defaults to 1 GB, hence -Xmx.
  container 'quay.io/biocontainers/juicertools:2.20.00--hdfd78af_0'
  memory { 24.GB * task.attempt }
  cpus 4
  time '48h'
  publishDir path: { "${params.outdir}/hic/contacts" }, mode: 'copy', pattern: "*.hic"
  tag { "${gmeta.assay}:${gmeta.group}" }

  input:
    tuple val(gmeta), path(pairs)
    path(fai)

  output:
    tuple val(gmeta), path("${gmeta.group}.hic"), emit: hic

  script:
    def heap = Math.max(1, (task.memory.toGiga() * 0.85) as int)
    """
    # No JVM perf-data file in /tmp: containers run with their own PID namespace but share /tmp, so two JVMs
    # with the same PID on one node clash on /tmp/hsperfdata_<user>/<pid> and crash with SIGBUS (JDK-8286030)
    export JAVA_TOOL_OPTIONS=-XX:-UsePerfData
    cut -f1,2 ${fai} > chrom.sizes
    mkdir -p tmp
    juicer_tools pre \\
      -Xmx${heap}g \\
      -Djava.io.tmpdir=\$PWD/tmp \\
      -j ${task.cpus} \\
      -t tmp \\
      -k VC,VC_SQRT,KR,SCALE \\
      ${params.juicerPreArgs} \\
      ${pairs} ${gmeta.group}.hic chrom.sizes
    """

  stub:
    """
    echo "-k VC,VC_SQRT,KR,SCALE ${params.juicerPreArgs}" > ${gmeta.group}.hic
    """
}
