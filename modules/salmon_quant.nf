process salmon_quant {
  container 'quay.io/biocontainers/salmon:2.8.0--hfa8f182_0'
  memory { 16.GB * task.attempt }
  cpus 8
  time '12h'
  publishDir "${params.outdir}/rna/quantification", mode: 'copy'
  tag { meta.id }

  input:
    tuple val(meta), path(reads, arity: '1..2')
    path(index)

  output:
    tuple val(meta), path("${meta.id}"), emit: quant

  script:
    def input = meta.single_end ? "-r ${reads[0]}" : "-1 ${reads[0]} -2 ${reads[1]}"
    """
    salmon quant \\
      -i ${index} \\
      -l A \\
      ${input} \\
      --numGibbsSamples ${params.salmonGibbs} \\
      -p ${task.cpus} \\
      -o ${meta.id}
    """

  stub:
    """
    mkdir ${meta.id}
    touch ${meta.id}/quant.sf
    """
}
