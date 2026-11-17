process macs3 {
  // Peaks per group on the merged BAM, with the group's control samples (if any) as -c.
  // MACS3 defaults are kept (including --keep-dup).
  container 'quay.io/biocontainers/macs3:3.0.5--py312h9639c01_0'
  memory { 12.GB * task.attempt }
  cpus 1
  time '12h'
  publishDir path: { "${params.outdir}/${gmeta.assay}/peaks" }, mode: 'copy', pattern: "*_peaks.{narrowPeak,broadPeak}"
  tag { "${gmeta.assay}:${gmeta.group}" }

  input:
    tuple val(gmeta), path(bam), path(bai), path(controls, arity: '0..*')
    val(genome_size)

  output:
    tuple val(gmeta), path("${gmeta.group}_peaks.{narrowPeak,broadPeak}"), emit: peaks
    path("${gmeta.group}_peaks.xls"), emit: qc

  script:
    def format = gmeta.single_end ? 'BAM' : 'BAMPE'
    def control = controls ? "-c ${controls.join(' ')}" : ''
    def broad = gmeta.peak_type == 'broad' ? '--broad' : ''
    """
    macs3 callpeak \\
      -t ${bam} \\
      ${control} \\
      -f ${format} \\
      -g ${genome_size} \\
      -n ${gmeta.group} \\
      --outdir . \\
      ${broad} ${params.macs3Args}
    """

  stub:
    def format = gmeta.single_end ? 'BAM' : 'BAMPE'
    def control = controls ? "-c ${controls.join(' ')}" : ''
    def broad = gmeta.peak_type == 'broad' ? '--broad' : ''
    """
    echo "-t ${bam} ${control} -f ${format} -g ${genome_size} ${broad} ${params.macs3Args}" > ${gmeta.group}_peaks.${gmeta.peak_type == 'broad' ? 'broadPeak' : 'narrowPeak'}
    touch ${gmeta.group}_peaks.xls
    """
}
