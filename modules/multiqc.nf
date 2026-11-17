process multiqc {
  container 'quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2'
  memory { 8.GB * task.attempt }
  cpus 4
  time '2h'
  publishDir "${params.outdir}/qc", mode: 'copy'

  input:
    path(qc, stageAs: '?/*')

  output:
    path("multiqc_report.html")
    path("multiqc_report_data")

  script:
    """
    multiqc --interactive -n multiqc_report.html -o . .
    """

  stub:
    """
    touch multiqc_report.html
    mkdir multiqc_report_data
    """
}
