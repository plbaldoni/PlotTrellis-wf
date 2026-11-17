process salmon_index {
  // Decoy-aware index: the whole genome is used as decoy sequence.
  // --gencode keeps only the transcript ID (with its version suffix) from GENCODE FASTA headers.
  container 'quay.io/biocontainers/salmon:2.8.0--hfa8f182_0'
  memory { 32.GB * task.attempt }
  cpus 16
  time '24h'
  storeDir { store_dir }

  input:
    val(store_dir)
    path(genome)
    path(transcripts)

  output:
    path("salmon_index")

  script:
    """
    grep '^>' ${genome} | cut -d ' ' -f 1 | sed 's/^>//' > decoys.txt
    cat ${transcripts} ${genome} > gentrome.fa

    salmon index \\
      -t gentrome.fa \\
      -d decoys.txt \\
      -i salmon_index \\
      --gencode \\
      -p ${task.cpus}

    rm gentrome.fa
    """

  stub:
    """
    mkdir salmon_index
    """
}
