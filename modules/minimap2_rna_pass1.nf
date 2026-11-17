process minimap2_rna_pass1 {
  // First pass of the 2-pass short-read RNA-seq alignment (minimap2 >= 2.29).
  // --write-junc reports one line per spliced read (primary alignments with MAPQ >= 10).
  // The same output is collapsed into junction counts: once per fragment (paired-end, mates
  // share the read name and are written consecutively) or once per read (single-end).
  container 'quay.io/biocontainers/minimap2:2.31--h118bc1c_0'
  memory { 24.GB * task.attempt }
  cpus 16
  time '24h'
  tag { meta.id }

  input:
    tuple val(meta), path(reads, arity: '1..2')
    path(index)
    path(annotation)

  output:
    tuple val(meta), path("${meta.id}.junc.bed.gz"), emit: junc
    tuple val(meta), path("${meta.id}.junc_counts.tsv"), emit: counts

  script:
    """
    minimap2 -x splice:sr -j ${annotation} --write-junc -t ${task.cpus} ${index} ${reads.join(' ')} \\
      | gzip -c > ${meta.id}.junc.bed.gz

    # chrom, intron start (0-based), intron end, strand, number of fragments
    zcat ${meta.id}.junc.bed.gz \\
      | awk -v OFS='\\t' '
          \$4 != prev { split("", seen); prev = \$4 }
          { k = \$1 OFS \$2 OFS \$3 OFS \$6; if (!(k in seen)) { seen[k] = 1; n[k]++ } }
          END { for (k in n) print k, n[k] }' \\
      > ${meta.id}.junc_counts.tsv
    """

  stub:
    """
    printf 'chr1\\t100\\t200\\t+\\t3\\n' > ${meta.id}.junc_counts.tsv
    echo -n | gzip -c > ${meta.id}.junc.bed.gz
    """
}
