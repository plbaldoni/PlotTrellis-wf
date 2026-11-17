process gtf2bed {
  // GENCODE GTF -> BED12 gene annotation for minimap2 -j (short RNA-seq reads)
  container 'quay.io/biocontainers/minimap2:2.31--h118bc1c_0'
  memory '8 GB'
  cpus 1
  time '1h'
  storeDir { store_dir }

  input:
    val(store_dir)
    path(gtf)

  output:
    path("annotation.bed12")

  script:
    """
    paftools.js gff2bed ${gtf} > annotation.bed12
    """

  stub:
    """
    touch annotation.bed12
    """
}
