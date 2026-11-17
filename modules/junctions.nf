process junctions {
  // Sums the per-sample junction counts of a group and writes a BED12 file with two
  // 1-bp blocks flanking each intron (score = number of supporting fragments/reads)
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory { 4.GB * task.attempt }
  cpus 1
  time '2h'
  publishDir "${params.outdir}/rna/junctions", mode: 'copy'
  tag { gmeta.group }

  input:
    tuple val(gmeta), path(counts)

  output:
    tuple val(gmeta), path("${gmeta.group}.junctions.bed"), emit: bed

  script:
    """
    cat ${counts} \\
      | awk -v OFS='\\t' '{ n[\$1 OFS \$2 OFS \$3 OFS \$4] += \$5 } END { for (k in n) print k, n[k] }' \\
      | sort -k1,1 -k2,2n -k3,3n \\
      | awk -v OFS='\\t' '{
          s = \$2 - 1; e = \$3 + 1
          print \$1, s, e, "JUNC" NR, \$5, \$4, s, e, "255,0,0", 2, "1,1", "0," (\$3 - s)
        }' \\
      > ${gmeta.group}.junctions.bed
    """
}
