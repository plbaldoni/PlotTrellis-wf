process sra_download {
  // Downloads one SRA run of a GEO sample: from NCBI's SRA bucket on AWS, or with prefetch if the run is not
  // there. vdb-validate checks the download, and fasterq-dump --split-3 writes the reads (for paired-end runs,
  // reads whose mate is missing are left out). With --keep-downloads (the default) the FASTQ files are stored
  // in <outdir>/fastq and are not downloaded again by later runs.
  container 'quay.io/biocontainers/mulled-v2-5f89fe0cd045cb1d615630b9261a1d17943a9b6a:2f4a4c900edd6801ff0068c2b3048b4459d119eb-0'
  memory { 4.GB * task.attempt }
  cpus 6
  time '24h'
  errorStrategy { task.attempt <= 3 ? 'retry' : 'finish' }   // downloads can fail for temporary network reasons
  maxRetries 3
  storeDir { Flags.on(params.keepDownloads) ? "${params.outdir}/fastq" : null }
  tag { "${name} (${sra.run})" }

  input:
    tuple val(meta), val(index), val(name), val(sra)

  output:
    tuple val(meta), val(index), val(name), path("${sra.run}_R?.fastq.gz", arity: '1..2'), emit: reads

  script:
    def run = sra.run
    def convert = sra.single_end ?
      """
      in=tmp/${run}.fastq
      [ -s \$in ] || in=tmp/${run}_1.fastq
      pigz -p ${task.cpus} -c \$in > ${run}_R1.fastq.gz
      """ :
      """
      if [ ! -s tmp/${run}_1.fastq ] || [ ! -s tmp/${run}_2.fastq ]; then
        echo "${run} is listed as paired-end, but fasterq-dump did not find read 1 and read 2." >&2
        exit 1
      fi
      pigz -p ${task.cpus} -c tmp/${run}_1.fastq > ${run}_R1.fastq.gz
      pigz -p ${task.cpus} -c tmp/${run}_2.fastq > ${run}_R2.fastq.gz
      """
    """
    if ! curl -fsSL --retry 5 --retry-delay 30 -o ${run}.sra https://sra-pub-run-odp.s3.amazonaws.com/sra/${run}/${run}; then
      echo "${run} is not in the SRA bucket on AWS; downloading it with prefetch." >&2
      rm -f ${run}.sra
      prefetch --max-size u --output-file ${run}.sra ${run}
    fi
    vdb-validate ${run}.sra
    mkdir -p tmp
    fasterq-dump --split-3 --threads ${task.cpus} --temp tmp --outdir tmp ${run}.sra
    ${convert}
    rm -rf tmp ${run}.sra
    """

  stub:
    """
    touch ${sra.run}_R1.fastq.gz
    ${sra.single_end ? '' : "touch ${sra.run}_R2.fastq.gz"}
    """
}
