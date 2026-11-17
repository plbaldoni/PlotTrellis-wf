process mean_tpm {
  // Mean TPM of each transcript over the samples of a group, written as a two-column quant.sf
  // (Name, TPM) in the transcript order of Salmon's output. Every sample must list the same transcripts
  container 'quay.io/biocontainers/samtools:1.23.1--ha83d96e_0'
  memory { 2.GB * task.attempt }
  cpus 1
  time '1h'
  publishDir "${params.outdir}/rna/quantification_mean", mode: 'copy'
  tag { gmeta.group }

  input:
    tuple val(gmeta), path(quant_dirs, arity: '1..*')

  output:
    tuple val(gmeta), path("${gmeta.group}/quant.sf"), emit: quant

  script:
    """
    mkdir ${gmeta.group}
    awk -F '\\t' -v OFS='\\t' '
      FNR == 1 {
        col = 0
        for (i = 1; i <= NF; i++) if (\$i == "TPM") col = i
        if (\$1 != "Name" || !col) { print "No Name/TPM header in " FILENAME > "/dev/stderr"; exit 1 }
        n_files++
        next
      }
      n_files == 1 { order[++n_tx] = \$1 }
      { sum[\$1] += \$col; seen[\$1]++ }
      END {
        if (n_files != ${quant_dirs.size()}) exit 1
        for (t in seen) if (seen[t] != n_files) { print "Transcript " t " is not in every quant.sf" > "/dev/stderr"; exit 1 }
        if (length(seen) != n_tx) { print "The quant.sf files list different transcripts" > "/dev/stderr"; exit 1 }
        print "Name", "TPM"
        for (i = 1; i <= n_tx; i++) printf "%s\\t%.6f\\n", order[i], sum[order[i]] / n_files
      }
    ' ${quant_dirs.collect { d -> "${d}/quant.sf" }.join(' ')} > ${gmeta.group}/quant.sf
    """

  stub:
    """
    mkdir ${gmeta.group}
    printf 'Name\\tTPM\\n' > ${gmeta.group}/quant.sf
    echo '# samples: ${quant_dirs.collect { d -> d.name }.sort().join(',')}' >> ${gmeta.group}/quant.sf
    """
}
