process blacklist_filter {
  // Removes reads overlapping blacklisted regions (only with --blacklist)
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory { 8.GB * task.attempt }
  cpus 4
  time '4h'
  tag { meta.id }

  input:
    tuple val(meta), path(bam), path(bai)
    path(blacklist)

  output:
    tuple val(meta), path("${meta.id}.filtered.bam"), path("${meta.id}.filtered.bam.bai"), emit: bam

  script:
    """
    samtools view -@ ${task.cpus} -b -L ${blacklist} -U ${meta.id}.filtered.bam -o /dev/null ${bam}
    samtools index ${meta.id}.filtered.bam
    """

  stub:
    """
    touch ${meta.id}.filtered.bam ${meta.id}.filtered.bam.bai
    """
}
