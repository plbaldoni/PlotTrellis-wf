process pairtools_dedup {
  // Removes duplicate pairs with pairtools defaults (both ends within 3 bp). Like dedup itself, keeps only
  // pairs with both sides mapped. With --hic-dedup false, duplicates are kept and only that selection is made.
  // The statistics (all pairs, before any removal) go to MultiQC.
  container 'quay.io/biocontainers/pairtools:1.1.3--py312h5219090_0'
  memory { 4.GB * task.attempt }
  cpus 4
  time '24h'
  tag { meta.id }

  input:
    tuple val(meta), path(pairs)

  output:
    tuple val(meta), path("${meta.id}.pairs.gz"), emit: pairs
    path("${meta.id}.pairs.stats"), emit: qc

  script:
    if (Flags.on(params.hicDedup))
      """
      export MPLCONFIGDIR=\$PWD/.matplotlib
      pairtools dedup \\
        --nproc-in 2 \\
        --nproc-out 2 \\
        --output ${meta.id}.pairs.gz \\
        --output-stats ${meta.id}.pairs.stats \\
        ${pairs}
      """
    else
      """
      export MPLCONFIGDIR=\$PWD/.matplotlib
      pairtools select --nproc-in 2 --nproc-out 2 '(chrom1 != "!") and (chrom2 != "!")' -o ${meta.id}.pairs.gz ${pairs}
      pairtools stats --nproc-in 2 -o ${meta.id}.pairs.stats ${pairs}
      """

  stub:
    """
    echo "dedup=${Flags.on(params.hicDedup)}" | gzip > ${meta.id}.pairs.gz
    touch ${meta.id}.pairs.stats
    """
}
