process bwa_hic {
  // Hi-C alignment. -SP aligns the two reads of a pair independently (no mate rescue, no pairing), as
  // pairtools recommends. Every record is kept, in read-name order, for pairtools parse.
  container 'quay.io/biocontainers/mulled-v2-fe8faa35dbf6dc65a0f7f5d4ea12e31a79f73e40:f45ad9036aa41bb10f875a330fa877d8869018a1-0'
  memory { 24.GB * task.attempt }
  cpus 32
  time '48h'
  tag { meta.id }

  input:
    tuple val(meta), path(reads, arity: '2')
    path(index)

  output:
    tuple val(meta), path("${meta.id}.bam"), emit: bam

  script:
    // The index folder holds one set of bwa index files; their common prefix is what bwa needs
    """
    prefix=\$(find -L ${index}/ -maxdepth 1 -name '*.bwt' | head -n 1 | sed 's/\\.bwt\$//')
    bwa mem -SP -t ${task.cpus} \${prefix} ${reads[0]} ${reads[1]} \\
      | samtools view -b -@ 4 -o ${meta.id}.bam -
    """

  stub:
    """
    touch ${meta.id}.bam
    """
}
