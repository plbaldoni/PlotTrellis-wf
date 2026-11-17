process minimap2_index {
  // The 'sr' (DNA) and 'splice:sr' (RNA) presets use different k-mer/window sizes, so each needs its own index
  container 'quay.io/biocontainers/minimap2:2.31--h118bc1c_0'
  memory { 32.GB * task.attempt }
  cpus 4
  time '6h'
  storeDir { store_dir }
  tag { preset }

  input:
    val(store_dir)
    path(genome)
    val(preset)
    val(name)

  output:
    path("${name}.mmi")

  script:
    """
    minimap2 -x ${preset} -t ${task.cpus} -d ${name}.mmi ${genome}
    """

  stub:
    """
    touch ${name}.mmi
    """
}
