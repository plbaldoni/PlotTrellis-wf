process coverage {
  // bamCoverage with its default chromosome handling. With --normalize-with-autosome,
  // everything except the autosomes is ignored when computing the scaling factor.
  container 'quay.io/biocontainers/deeptools:3.5.6--pyhdfd78af_0'
  memory { 8.GB * task.attempt }
  cpus 8
  time '8h'
  publishDir path: { "${params.outdir}/${gmeta.assay}/coverage" }, mode: 'copy'
  tag { "${gmeta.assay}:${gmeta.group}" }

  input:
    tuple val(gmeta), path(bam), path(bai)
    path(fai)
    val(normalization)
    val(autosome_regex)

  output:
    tuple val(gmeta), path("${gmeta.group}.bw"), emit: bw

  script:
    def ignore = Flags.on(params.normalizeWithAutosome) ?
      "--ignoreForNormalization \$(cut -f 1 ${fai} | grep -vxE '${autosome_regex}' | tr '\\n' ' ')" : ''
    """
    bamCoverage --verbose ${normalization} --binSize 10 ${ignore} \\
      --bam ${bam} \\
      --outFileName ${gmeta.group}.bw \\
      --outFileFormat bigwig \\
      --numberOfProcessors ${task.cpus}
    """

  stub:
    def ignore = Flags.on(params.normalizeWithAutosome) ?
      "--ignoreForNormalization \$(cut -f 1 ${fai} | grep -vxE '${autosome_regex}' | tr '\\n' ' ')" : ''
    """
    echo "${normalization} ${ignore}" > ${gmeta.group}.bw
    """
}
