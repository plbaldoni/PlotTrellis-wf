include { bwa_index } from '../modules/bwa_index'
include { bwa_hic } from '../modules/bwa_hic'
include { pairtools_parse } from '../modules/pairtools_parse'
include { pairtools_dedup } from '../modules/pairtools_dedup'
include { pairtools_merge } from '../modules/pairtools_merge'
include { juicer_pre } from '../modules/juicer_pre'

workflow HIC {
  take:
    ch_reads         // [meta, [fastq_1, fastq_2]] for hic samples
    store_dir        // reference directory for this species/GENCODE release
    genome
    fai

  main:
    if ( params.bwaIndex ) {
      ch_bwa = channel.value(file(params.bwaIndex, checkIfExists: true))
    }
    else {
      ch_bwa = bwa_index(store_dir, genome)
    }

    // Alignment, pairs and duplicate removal (per sample)
    bwa_hic(ch_reads, ch_bwa)
    pairtools_parse(bwa_hic.out.bam, fai)
    pairtools_dedup(pairtools_parse.out.pairs)

    // Contact map per group (each group starts as soon as its own samples are done)
    ch_group_pairs = pairtools_dedup.out.pairs
      | map { meta, pairs -> [ groupKey("${meta.assay}__${meta.group}".toString(), meta.group_size), meta, pairs ] }
      | groupTuple(sort: 'hash')
      | map { _key, metas, pairs -> [ Samplesheet.groupMeta(metas), pairs ] }

    pairtools_merge(ch_group_pairs)
    juicer_pre(pairtools_merge.out.pairs, fai)

  emit:
    qc = pairtools_dedup.out.qc
}
