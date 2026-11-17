process download_reference {
  // Decompresses the GENCODE genome (primary assembly), comprehensive PRI annotation and
  // transcript sequences. Nextflow downloads the files (inputs are https URLs); the results
  // are stored once per species/release in params.refDir and reused by later runs.
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory '4 GB'
  cpus 1
  time '4h'
  storeDir { store_dir }

  input:
    val(store_dir)
    path(genome_gz)
    path(gtf_gz)
    path(transcripts_gz)

  output:
    path("genome.fa"), emit: genome
    path("annotation.gtf"), emit: gtf
    path("transcripts.fa"), emit: transcripts

  script:
    """
    gunzip -c ${genome_gz} > genome.fa
    gunzip -c ${gtf_gz} > annotation.gtf
    gunzip -c ${transcripts_gz} > transcripts.fa
    """

  stub:
    """
    printf '>chr1\\nACGT\\n>chrX\\nACGT\\n>GL000008.2\\nACGT\\n' > genome.fa
    touch annotation.gtf transcripts.fa
    """
}
