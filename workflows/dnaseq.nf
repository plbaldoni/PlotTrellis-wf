include { minimap2_index } from '../modules/minimap2_index'
include { minimap2_dna } from '../modules/minimap2_dna'
include { blacklist_filter } from '../modules/blacklist_filter'
include { merge_bams } from '../modules/merge_bams'
include { coverage } from '../modules/coverage'
include { macs3 } from '../modules/macs3'

workflow DNASEQ {
  take:
    ch_reads         // [meta, [fastq_1, (fastq_2)]] for atac, chip, cutrun and cuttag samples
    store_dir        // reference directory for this species/GENCODE release
    genome
    fai
    blacklist        // BED file (only used with --blacklist)
    genome_size      // effective genome size for RPGC and MACS3
    autosome_regex

  main:
    if ( params.minimap2IndexDna ) {
      ch_mmi = channel.value(file(params.minimap2IndexDna, checkIfExists: true))
    }
    else {
      ch_mmi = minimap2_index(store_dir, genome, 'sr', 'minimap2_sr')
    }

    // Alignment (per sample)
    minimap2_dna(ch_reads, ch_mmi)

    if ( GenomeRefs.blacklistMode(params.blacklist) != 'off' ) {
      blacklist_filter(minimap2_dna.out.bam, blacklist)
      ch_bam = blacklist_filter.out.bam
    }
    else {
      ch_bam = minimap2_dna.out.bam
    }

    // Combine the samples of each group (treatment and control groups alike). Each group starts as soon as
    // its own samples are aligned
    ch_group_bams = ch_bam
      | map { meta, bam, _bai -> [ groupKey("${meta.assay}__${meta.group}".toString(), meta.group_size), meta, bam ] }
      | groupTuple(sort: 'hash')
      | map { _key, metas, bams -> [ Samplesheet.groupMeta(metas), bams ] }

    merge_bams(ch_group_bams)

    // Coverage for every group, including control groups
    coverage(merge_bams.out.bam, fai, genome_size.map { size -> "--normalizeUsing RPGC --effectiveGenomeSize ${size}" }, autosome_regex)

    // Controls of each treatment group: [group key, [control BAMs]], ready once all of the group's controls are aligned
    ch_control_bams = ch_bam
      | filter { meta, _bam, _bai -> meta.is_control }
      | map { meta, bam, _bai -> [ meta.id, bam ] }

    ch_group_controls = ch_reads
      | filter { meta, _reads -> !meta.is_control && meta.controls }
      | flatMap { meta, _reads -> meta.controls.collect { c -> [ c, "${meta.assay}__${meta.group}".toString(), meta.group_controls.size() ] } }
      | unique
      | combine(ch_control_bams, by: 0)
      | map { _control_id, key, n, bam -> [ groupKey(key, n), bam ] }
      | groupTuple(sort: 'hash')
      | map { key, bams -> [ key.toString(), bams ] }

    // Peaks for treatment groups only
    ch_treatment = merge_bams.out.bam
      | filter { gmeta, _bam, _bai -> !gmeta.is_control }
      | branch { gmeta, _bam, _bai ->
          with_controls: gmeta.controls.size() > 0
          no_controls: true
        }

    ch_macs3 = ch_treatment.with_controls
      | map { gmeta, bam, bai -> [ gmeta.key, gmeta, bam, bai ] }
      | join(ch_group_controls)
      | map { _key, gmeta, bam, bai, controls -> [ gmeta, bam, bai, controls ] }
      | mix(ch_treatment.no_controls.map { gmeta, bam, bai -> [ gmeta, bam, bai, [] ] })

    macs3(ch_macs3, genome_size)

  emit:
    qc = minimap2_dna.out.qc.flatten().mix(macs3.out.qc)
}
