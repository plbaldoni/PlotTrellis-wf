process merge_fastq {
  // Joins the FASTQ files of a sample's technical replicates (read 1 with read 1, read 2 with read 2).
  // Joined gzip files are valid gzip files, so nothing is decompressed.
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory '2 GB'
  cpus 1
  time '8h'
  tag { meta.id }

  input:
    tuple val(meta), path(fastq_1, arity: '1..*', stageAs: 'r1_?/*'), path(fastq_2, arity: '0..*', stageAs: 'r2_?/*')

  output:
    tuple val(meta), path("${meta.id}_R?.fastq*", arity: '1..2'), emit: reads

  script:
    def ext = fastq_1[0].name.endsWith('.gz') ? 'fastq.gz' : 'fastq'
    def read2 = fastq_2 ? "cat ${fastq_2.join(' ')} > ${meta.id}_R2.${ext}" : ''
    """
    cat ${fastq_1.join(' ')} > ${meta.id}_R1.${ext}
    ${read2}
    """

  stub:
    def ext = fastq_1[0].name.endsWith('.gz') ? 'fastq.gz' : 'fastq'
    """
    touch ${meta.id}_R1.${ext}
    ${fastq_2 ? "touch ${meta.id}_R2.${ext}" : ''}
    """
}
