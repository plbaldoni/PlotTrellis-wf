process minimap2_dna {
  // Short-read genomic alignment. Only unmapped reads are removed
  // (paired-end: both mates must be mapped). Duplicates are kept.
  container 'quay.io/biocontainers/mulled-v2-66534bcbb7031a148b13e2ad42583020b9cd25c4:b411340b52d82a9c276d87c7a3dcffc880be762f-0'
  memory { 32.GB * task.attempt }
  cpus 32
  time '48h'
  tag { meta.id }

  input:
    tuple val(meta), path(reads, arity: '1..2')
    path(index)

  output:
    tuple val(meta), path("${meta.id}.bam"), path("${meta.id}.bam.bai"), emit: bam
    path("${meta.id}.{stats,flagstat}"), emit: qc

  script:
    def flag = meta.single_end ? 4 : 12
    """
    minimap2 -ax sr -t ${task.cpus} ${index} ${reads.join(' ')} \\
      | samtools view -u -F ${flag} - \\
      | samtools sort -@ 4 -m 2G -T ${meta.id}.tmp -o ${meta.id}.bam -

    samtools index ${meta.id}.bam
    samtools stats ${meta.id}.bam > ${meta.id}.stats
    samtools flagstat ${meta.id}.bam > ${meta.id}.flagstat
    """

  stub:
    """
    touch ${meta.id}.bam ${meta.id}.bam.bai ${meta.id}.stats ${meta.id}.flagstat
    """
}
