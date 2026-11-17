process faidx {
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory '4 GB'
  cpus 1
  time '1h'
  storeDir { store_dir }

  input:
    val(store_dir)
    path(genome)

  output:
    path("genome.fa.fai")

  script:
    """
    samtools faidx ${genome}
    """

  stub:
    """
    printf 'chr1\\t4\\t6\\t4\\t5\\nchrX\\t4\\t17\\t4\\t5\\nGL000008.2\\t4\\t28\\t4\\t5\\n' > genome.fa.fai
    """
}
