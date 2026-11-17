process pairtools_parse {
  // Contact pairs from the alignments, with pairtools defaults (--min-mapq 1, --walks-policy 5unique),
  // then sorted. --drop-sam leaves the alignment records out of the pairs file.
  container 'quay.io/biocontainers/pairtools:1.1.3--py312h5219090_0'
  memory { 16.GB * task.attempt }
  cpus 4
  time '24h'
  tag { meta.id }

  input:
    tuple val(meta), path(bam)
    path(fai)

  output:
    tuple val(meta), path("${meta.id}.sorted.pairs.gz"), emit: pairs

  script:
    def sort_memory = Math.max(1, (task.memory.toGiga() / 2) as int)
    """
    export MPLCONFIGDIR=\$PWD/.matplotlib
    cut -f1,2 ${fai} > chrom.sizes
    pairtools parse \\
      --chroms-path chrom.sizes \\
      --drop-sam \\
      --nproc-in 2 \\
      --nproc-out 2 \\
      ${params.pairtoolsParseArgs} \\
      ${bam} \\
      | pairtools sort --nproc ${task.cpus} --memory ${sort_memory}G --tmpdir . -o ${meta.id}.sorted.pairs.gz
    """

  stub:
    """
    echo "--chroms-path --drop-sam ${params.pairtoolsParseArgs}" | gzip > ${meta.id}.sorted.pairs.gz
    """
}
