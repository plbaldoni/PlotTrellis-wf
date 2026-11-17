process pairtools_merge {
  // Combines the pairs of all samples in a group (applying --pairtools-select, if given) and keeps only the
  // header lines that juicer_tools pre reads: it fails on the '#chromsize:' lines that pairtools writes
  container 'quay.io/biocontainers/pairtools:1.1.3--py312h5219090_0'
  memory { 4.GB * task.attempt }
  cpus 4
  time '24h'
  tag { "${gmeta.assay}:${gmeta.group}" }

  input:
    tuple val(gmeta), path(pairs, arity: '1..*')

  output:
    tuple val(gmeta), path("${gmeta.group}.pairs.gz"), emit: pairs

  script:
    def combine = pairs.size() == 1
      ? "bgzip -dc -@ 4 ${pairs[0]}"
      : "pairtools merge --nproc ${task.cpus} --nproc-in 2 --nproc-out 2 ${pairs.join(' ')}"
    def select = params.pairtoolsSelect ? "| pairtools select '${params.pairtoolsSelect}'" : ''
    """
    export MPLCONFIGDIR=\$PWD/.matplotlib
    ${combine} ${select} \\
      | awk '!/^#/ || /^## pairs format/ || /^#columns:/' \\
      | bgzip -@ ${task.cpus} > ${gmeta.group}.pairs.gz
    """

  stub:
    def select = params.pairtoolsSelect ? "| pairtools select '${params.pairtoolsSelect}'" : ''
    """
    echo "${pairs.size()} file(s) ${select}" | gzip > ${gmeta.group}.pairs.gz
    """
}
