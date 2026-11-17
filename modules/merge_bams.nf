process merge_bams {
  // Combines the BAMs of all samples in a group
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory { 4.GB * task.attempt }
  cpus 8
  time '8h'
  tag { "${gmeta.assay}:${gmeta.group}" }

  input:
    tuple val(gmeta), path(bams, arity: '1..*')

  output:
    tuple val(gmeta), path("${gmeta.group}.merged.bam"), path("${gmeta.group}.merged.bam.bai"), emit: bam

  script:
    if (bams.size() == 1)
      """
      ln -s ${bams[0]} ${gmeta.group}.merged.bam
      samtools index ${gmeta.group}.merged.bam
      """
    else
      """
      samtools merge -@ ${task.cpus} -o ${gmeta.group}.merged.bam ${bams.join(' ')}
      samtools index ${gmeta.group}.merged.bam
      """

  stub:
    """
    touch ${gmeta.group}.merged.bam ${gmeta.group}.merged.bam.bai
    """
}
