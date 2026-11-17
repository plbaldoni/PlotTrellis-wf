include { minimap2_index } from '../modules/minimap2_index'
include { gtf2bed } from '../modules/gtf2bed'
include { salmon_index } from '../modules/salmon_index'
include { salmon_quant } from '../modules/salmon_quant'
include { minimap2_rna_pass1 } from '../modules/minimap2_rna_pass1'
include { minimap2_rna_pass2 } from '../modules/minimap2_rna_pass2'
include { merge_bams } from '../modules/merge_bams'
include { coverage } from '../modules/coverage'
include { junctions } from '../modules/junctions'
include { mean_tpm } from '../modules/mean_tpm'

workflow RNASEQ {
  take:
    ch_reads         // [meta, [fastq_1, (fastq_2)]]
    store_dir        // reference directory for this species/GENCODE release
    genome
    gtf
    transcripts
    fai
    autosome_regex

  main:
    // Indexes: use the ones provided by the user, otherwise build (and store) them
    if ( params.minimap2IndexRna ) {
      ch_mmi = channel.value(file(params.minimap2IndexRna, checkIfExists: true))
    }
    else {
      ch_mmi = minimap2_index(store_dir, genome, 'splice:sr', 'minimap2_splice_sr')
    }

    if ( params.salmonIndex ) {
      ch_salmon_index = channel.value(file(params.salmonIndex, checkIfExists: true))
    }
    else {
      ch_salmon_index = salmon_index(store_dir, genome, transcripts)
    }

    ch_annotation = gtf2bed(store_dir, gtf)

    // Quantification (per sample)
    ch_quant = salmon_quant(ch_reads, ch_salmon_index)

    // Mean TPM per group (each group starts as soon as its own samples are quantified)
    ch_group_quant = ch_quant
      | map { meta, dir -> [ groupKey("${meta.assay}__${meta.group}".toString(), meta.group_size), meta, dir ] }
      | groupTuple(sort: 'hash')
      | map { _key, metas, dirs -> [ Samplesheet.groupMeta(metas), dirs ] }

    mean_tpm(ch_group_quant)

    // 2-pass spliced alignment (per sample)
    minimap2_rna_pass1(ch_reads, ch_mmi, ch_annotation)
    minimap2_rna_pass2(ch_reads.join(minimap2_rna_pass1.out.junc), ch_mmi, ch_annotation)

    // Coverage per group (each group starts as soon as its own samples are aligned)
    ch_group_bams = minimap2_rna_pass2.out.bam
      | map { meta, bam, _bai -> [ groupKey("${meta.assay}__${meta.group}".toString(), meta.group_size), meta, bam ] }
      | groupTuple(sort: 'hash')
      | map { _key, metas, bams -> [ Samplesheet.groupMeta(metas), bams ] }

    merge_bams(ch_group_bams)
    coverage(merge_bams.out.bam, fai, '--normalizeUsing CPM', autosome_regex)

    // Splice junctions per group
    ch_group_junctions = minimap2_rna_pass1.out.counts
      | map { meta, counts -> [ groupKey("${meta.assay}__${meta.group}".toString(), meta.group_size), meta, counts ] }
      | groupTuple(sort: 'hash')
      | map { _key, metas, counts -> [ Samplesheet.groupMeta(metas), counts ] }

    junctions(ch_group_junctions)

  emit:
    qc = minimap2_rna_pass2.out.qc.flatten().mix(ch_quant.map { _meta, dir -> dir })
}
