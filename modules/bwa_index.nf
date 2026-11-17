process bwa_index {
  // bwa index of the genome (Hi-C only)
  container 'quay.io/biocontainers/mulled-v2-fe8faa35dbf6dc65a0f7f5d4ea12e31a79f73e40:f45ad9036aa41bb10f875a330fa877d8869018a1-0'
  memory { 8.GB * task.attempt }
  cpus 1
  time '12h'
  storeDir { store_dir }

  input:
    val(store_dir)
    path(genome)

  output:
    path("bwa")

  script:
    """
    mkdir bwa
    bwa index -p bwa/genome ${genome}
    """

  stub:
    """
    mkdir bwa
    touch bwa/genome.amb bwa/genome.ann bwa/genome.bwt bwa/genome.pac bwa/genome.sa
    """
}
