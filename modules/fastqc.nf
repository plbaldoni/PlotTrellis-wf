process fastqc {
  container 'quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0'
  memory { 4.GB * task.attempt }
  cpus 4
  time '4h'
  publishDir "${params.outdir}/qc/fastqc", mode: 'copy'
  tag { name }

  input:
    tuple val(name), path(reads, arity: '1..2', stageAs: 'input?/*')

  output:
    path("*_fastqc.{zip,html}"), emit: qc

  script:
    // Reports are named after the sample (and technical replicate), not the original file names
    def links = reads.withIndex().collect { f, i -> "${name}_R${i + 1}.${f.name.endsWith('.gz') ? 'fastq.gz' : 'fastq'}" }
    def commands = [reads, links].transpose().collect { f, link -> "ln -s ${f} ${link}" }
    """
    # No JVM perf-data file in /tmp: containers run with their own PID namespace but share /tmp, so two JVMs
    # with the same PID on one node clash on /tmp/hsperfdata_<user>/<pid> and crash with SIGBUS (JDK-8286030)
    export JAVA_TOOL_OPTIONS=-XX:-UsePerfData
    ${commands.join('\n')}
    fastqc --threads ${task.cpus} --format fastq ${links.join(' ')}
    """

  stub:
    """
    touch ${name}_R1_fastqc.zip ${name}_R1_fastqc.html
    """
}
