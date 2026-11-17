process publish_gtf {
  // Copy of the GENCODE annotation used by the run, in the results (<outdir>/reference/), for the
  // PlotTrellis app. Compressed from the stored GTF, so runs that reuse stored references need no download
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory '2 GB'
  cpus 4
  time '1h'
  publishDir "${params.outdir}/reference", mode: 'copy'

  input:
    path(gtf)
    val(name)

  output:
    path(name)

  script:
    """
    bgzip -@ ${task.cpus} -c ${gtf} > ${name}
    """

  stub:
    """
    touch ${name}
    """
}
