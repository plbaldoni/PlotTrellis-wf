process fastp {
  // Optional read trimming (--trim). fastp defaults (adapter trimming, quality and length filters) plus
  // poly-G tail trimming, which fastp only turns on by itself when the read names carry a two-colour
  // instrument ID, and adapter detection for paired-end reads (catches adapter dimers).
  container 'quay.io/biocontainers/fastp:1.4.0--h43da1c4_0'
  memory { 4.GB * task.attempt }
  cpus 8
  time '8h'
  publishDir "${params.outdir}/qc/fastp", mode: 'copy', pattern: "*.fastp.{json,html}"
  tag { meta.id }

  input:
    tuple val(meta), path(reads, arity: '1..2', stageAs: 'input?/*')

  output:
    tuple val(meta), path("${meta.id}_R?.trimmed.fastq.gz", arity: '1..2'), emit: reads
    path("${meta.id}.fastp.json"), emit: qc
    path("${meta.id}.fastp.html")

  script:
    // Inputs are linked as <sample>_R1/R2 so that reports are labelled by sample
    def links = reads.withIndex().collect { f, i -> "${meta.id}_R${i + 1}.${f.name.endsWith('.gz') ? 'fastq.gz' : 'fastq'}" }
    def commands = [reads, links].transpose().collect { f, link -> "ln -s ${f} ${link}" }
    def io = meta.single_end
      ? "-i ${links[0]} -o ${meta.id}_R1.trimmed.fastq.gz"
      : "-i ${links[0]} -I ${links[1]} -o ${meta.id}_R1.trimmed.fastq.gz -O ${meta.id}_R2.trimmed.fastq.gz --detect_adapter_for_pe"
    """
    ${commands.join('\n')}
    fastp ${io} \\
      --trim_poly_g \\
      --thread ${task.cpus} \\
      --json ${meta.id}.fastp.json \\
      --html ${meta.id}.fastp.html \\
      ${params.trimArgs}
    """

  stub:
    def io = meta.single_end ? '' : '-I -O --detect_adapter_for_pe'
    """
    echo "-i -o ${io} --trim_poly_g ${params.trimArgs}" | gzip > ${meta.id}_R1.trimmed.fastq.gz
    ${meta.single_end ? '' : "touch ${meta.id}_R2.trimmed.fastq.gz"}
    touch ${meta.id}.fastp.json ${meta.id}.fastp.html
    """
}
