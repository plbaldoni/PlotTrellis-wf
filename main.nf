#!/usr/bin/env nextflow

/*
 * PlotTrellis-wf: processes raw sequencing data into the files used by the PlotTrellis Shiny app.
 *
 *   RNA-seq                  -> Salmon quant.sf (per sample), bigWig and splice-junction BED12 (per group)
 *   ATAC, ChIP, CUT&RUN/Tag  -> bigWig and MACS3 peaks (per group)
 *   Hi-C                     -> .hic contact map (per group)
 *
 * See README.md for usage. Parameter defaults are in nextflow.config.
 */

include { download_reference } from './modules/download_reference'
include { faidx } from './modules/faidx'
include { fastp } from './modules/fastp'
include { fastqc } from './modules/fastqc'
include { merge_fastq } from './modules/merge_fastq'
include { multiqc } from './modules/multiqc'
include { publish_gtf } from './modules/publish_gtf'
include { sra_download } from './modules/sra_download'
include { RNASEQ } from './workflows/rnaseq'
include { DNASEQ } from './workflows/dnaseq'
include { HIC } from './workflows/hic'

workflow {

  // Keep a copy of Nextflow's log (.nextflow.log, written in the launch folder) with the results, and after a
  // successful run write the PlotTrellis app's samples.txt (app_samples, set below once the samplesheet is read).
  // The values are taken here because `workflow` is not visible inside the handler
  def wf_meta = workflow
  def nf_log = workflow.launchDir.resolve('.nextflow.log')
  def nf_log_copy = params.outdir ? file("${params.outdir}/logs/nextflow_${workflow.start.format(java.time.format.DateTimeFormatter.ofPattern('yyyyMMdd_HHmmss'))}.log") : null
  def app_samples = [:]
  workflow.onComplete {
    if ( nf_log_copy && nf_log.exists() ) {
      nf_log_copy.parent.mkdirs()
      nf_log.copyTo(nf_log_copy)
    }
    if ( wf_meta.success && app_samples.groups ) {
      def outdir = app_samples.outdir
      def text = AppSamples.build(app_samples.groups, outdir, app_samples.info + [date: new Date().format('yyyy-MM-dd HH:mm')])
      if ( text ) {
        outdir.resolve('samples.txt').text = text
        println "PlotTrellis app samples file: ${outdir.resolve('samples.txt')}"
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Check options
  // ---------------------------------------------------------------------------
  def problems = []
  if ( !params.samplesheet ) problems << "--samplesheet is required (path to your .xlsx samplesheet)."
  if ( !params.outdir ) problems << "--outdir is required (folder where the results will be saved)."
  if ( !(params.species in ['human', 'mouse']) ) problems << "--species is required and must be 'human' or 'mouse'."
  if ( !(params.peakType in ['narrow', 'broad']) ) problems << "--peak-type must be 'narrow' or 'broad'."
  def trim_selection = Flags.isTrue(params.trim) ? ['all'] : (Flags.isFalse(params.trim) ? [] : params.trim.toString().toLowerCase().split(/[,\s]+/).findAll { a -> a })
  def trim_unknown = trim_selection.findAll { a -> !(a in Samplesheet.ASSAYS + ['all', 'true']) }
  if ( trim_unknown ) problems << "--trim: unknown assay(s) ${trim_unknown.join(', ')}. Use --trim on its own for every assay, or a comma-separated list of: ${Samplesheet.ASSAYS.join(', ')}."
  if ( problems ) error("Please fix the following:\n  - " + problems.join("\n  - "))

  def sheet = Samplesheet.load(file(params.samplesheet).toString(), params.assay, params.peakType, params.species)
  sheet.warnings.each { w -> log.warn(w) }
  if ( sheet.errors ) error("Problems found in the samplesheet ${params.samplesheet}:\n  - " + sheet.errors.join("\n  - "))

  def release
  try {
    release = GenomeRefs.resolveRelease(params.species, params.gencode)
  } catch ( IllegalArgumentException e ) {
    error(e.message)
  }
  def urls = GenomeRefs.urls(params.species, release)
  if ( !GenomeRefs.exists(urls.genome) ) error("GENCODE release '${release}' was not found for ${params.species} (${urls.genome}). Check --gencode.")

  def store_dir = "${params.refDir}/${params.species}/gencode_${release}"
  def genome_size = params.effectiveGenomeSize ?: GenomeRefs.EFFECTIVE_GENOME_SIZE[params.species]
  def autosome_regex = GenomeRefs.AUTOSOME_REGEX[params.species]
  def blacklist_mode = GenomeRefs.blacklistMode(params.blacklist)
  def assays = sheet.samples.collect { s -> s.meta.assay }.unique()
  def trim_assays = trim_selection.any { a -> a in ['all', 'true'] } ? assays : assays.findAll { a -> a in trim_selection }
  def n_runs = sheet.samples.sum { s -> s.runs.size() }
  def downloads = sheet.samples.findAll { s -> s.runs.any { run -> run.sra } }
  def keep_downloads = Flags.on(params.keepDownloads)
  def fastq_dir = "${file(params.outdir)}/fastq"
  app_samples.putAll(groups: sheet.app_groups, outdir: file(params.outdir),
                     info: [version: workflow.manifest.version, species: params.species, gtf: "reference/${urls.gtf.tokenize('/')[-1]}".toString()])

  log.info """
  ==========================================================
   PlotTrellis-wf ${workflow.manifest.version}
  ==========================================================
   Samplesheet       : ${params.samplesheet}
   Output folder     : ${params.outdir}
   Assays            : ${assays.join(', ')}
   Samples           : ${sheet.samples.size()}${n_runs > sheet.samples.size() ? " (${n_runs} technical replicates)" : ''}${downloads ? "\n   From GEO          : ${downloads.size()} samples, ${downloads.sum { s -> s.runs.size() }} SRA runs (${keep_downloads ? "kept in ${fastq_dir}" : 'not kept'})" : ''}
   Species           : ${params.species} (${GenomeRefs.ASSEMBLY[params.species]}, GENCODE ${release})
   References        : ${store_dir}
   Work folder       : ${workflow.workDir}
   Read trimming     : ${trim_assays ? "fastp (${trim_assays.join(', ')})" : 'off'}
   Blacklist         : ${blacklist_mode == 'custom' ? params.blacklist : blacklist_mode}
   Autosome-only norm: ${Flags.on(params.normalizeWithAutosome)}
   Peak type default : ${params.peakType}${'hic' in assays ? "\n   Hi-C duplicates   : ${Flags.on(params.hicDedup) ? 'removed' : 'kept'}" : ''}
   Partition/queue   : ${params.partition ?: 'scheduler default'}
  ==========================================================
  """.stripIndent()

  // Keep a record of the validated samplesheet and references used
  def info_dir = file("${params.outdir}/logs/pipeline_info")
  info_dir.mkdirs()
  file("${info_dir}/samplesheet.validated.csv").text = Samplesheet.toCsv(sheet.samples, keep_downloads ? fastq_dir : '')
  file("${info_dir}/references.txt").text = """\
    species: ${params.species}
    assembly: ${GenomeRefs.ASSEMBLY[params.species]}
    gencode_release: ${release}
    genome: ${urls.genome}
    annotation: ${urls.gtf}
    transcripts: ${urls.transcripts}
    effective_genome_size: ${genome_size}
    blacklist: ${blacklist_mode == 'default' ? GenomeRefs.BLACKLIST_FILE[params.species] : (blacklist_mode == 'custom' ? params.blacklist : 'none')}
    """.stripIndent()

  // ---------------------------------------------------------------------------
  // Inputs and references
  // ---------------------------------------------------------------------------
  // One entry per technical replicate: [meta, index, name, [fastq_1, (fastq_2)]]. Local FASTQ files are used as
  // they are; the SRA runs of GEO samples (rows with a GSM and no FASTQ files) are downloaded first
  def runs = sheet.samples.collectMany { s -> s.runs.withIndex().collect { run, i -> [s.meta, i, run] } }
  ch_local = channel.fromList(runs.findAll { entry -> !entry[2].sra })
    | map { meta, i, run -> [ meta, i, run.name, run.reads.collect { f -> file(f, checkIfExists: true) } ] }
  sra_download(
    channel.fromList(runs.findAll { entry -> entry[2].sra })
      | map { meta, i, run -> [ meta, i, run.name, run.sra ] }
  )
  ch_runs = ch_local.mix(sra_download.out.reads)

  // One entry per sample: [meta, [fastq_1, (fastq_2)]]. The FASTQ files of technical replicates are merged
  def n_runs_of = sheet.samples.collectEntries { s -> [ (s.meta.id): s.runs.size() ] }
  ch_by_sample = ch_runs
    | map { meta, i, _name, reads -> [ groupKey(meta.id, n_runs_of[meta.id]), meta, i, reads ] }
    | groupTuple()
    | map { _id, metas, idx, reads -> [ metas[0], [idx, reads].transpose().sort { a -> a[0] }.collect { a -> a[1] } ] }
    | branch { _meta, reads ->
        single: reads.size() == 1
        merge: true
      }
  merge_fastq(
    ch_by_sample.merge.map { meta, reads -> [ meta, reads.collect { r -> r[0] }, reads.findAll { r -> r.size() > 1 }.collect { r -> r[1] } ] }
  )

  ch_samples = ch_by_sample.single.map { meta, reads -> [ meta, reads[0] ] }
    | mix(merge_fastq.out.reads.map { meta, reads -> [ meta, reads.sort(false) { f -> f.name } ] })

  // Optional read trimming (--trim), per sample after merging
  ch_to_trim = ch_samples.branch { meta, _reads ->
    trim: meta.assay in trim_assays
    keep: true
  }
  fastp(ch_to_trim.trim)
  ch_reads = ch_to_trim.keep
    | mix(fastp.out.reads.map { meta, reads -> [ meta, reads.sort(false) { f -> f.name } ] })

  // GENCODE files: reuse the stored copies, otherwise download (by Nextflow) and decompress them
  def stored = [genome: file("${store_dir}/genome.fa"), gtf: file("${store_dir}/annotation.gtf"), transcripts: file("${store_dir}/transcripts.fa")]
  if ( stored.values().every { f -> f.exists() } ) {
    ch_genome = channel.value(stored.genome)
    ch_gtf = channel.value(stored.gtf)
    ch_transcripts = channel.value(stored.transcripts)
  }
  else {
    download_reference(store_dir, file(urls.genome), file(urls.gtf), file(urls.transcripts))
    ch_genome = download_reference.out.genome
    ch_gtf = download_reference.out.gtf
    ch_transcripts = download_reference.out.transcripts
  }
  ch_fai = faidx(store_dir, ch_genome)

  // The annotation goes with the results (<outdir>/reference/), under GENCODE's file name, for the app
  publish_gtf(ch_gtf, urls.gtf.tokenize('/')[-1])

  if ( blacklist_mode == 'default' ) {
    ch_blacklist = channel.value(file("${projectDir}/${GenomeRefs.BLACKLIST_FILE[params.species]}", checkIfExists: true))
  }
  else if ( blacklist_mode == 'custom' ) {
    ch_blacklist = channel.value(file(params.blacklist, checkIfExists: true))
  }
  else {
    ch_blacklist = channel.value([])
  }

  // ---------------------------------------------------------------------------
  // QC and assays
  // ---------------------------------------------------------------------------
  fastqc(ch_runs.map { _meta, _i, name, reads -> [ name, reads ] })
  ch_qc = fastqc.out.qc.flatten().mix(fastp.out.qc)

  if ( 'rna' in assays ) {
    RNASEQ(
      ch_reads.filter { meta, _reads -> meta.assay == 'rna' },
      store_dir,
      ch_genome,
      ch_gtf,
      ch_transcripts,
      ch_fai,
      autosome_regex
    )
    ch_qc = ch_qc.mix(RNASEQ.out.qc)
  }

  if ( assays.any { a -> a in Samplesheet.DNA_ASSAYS } ) {
    DNASEQ(
      ch_reads.filter { meta, _reads -> meta.assay in Samplesheet.DNA_ASSAYS },
      store_dir,
      ch_genome,
      ch_fai,
      ch_blacklist,
      channel.value(genome_size),
      autosome_regex
    )
    ch_qc = ch_qc.mix(DNASEQ.out.qc)
  }

  if ( 'hic' in assays ) {
    HIC(
      ch_reads.filter { meta, _reads -> meta.assay == 'hic' },
      store_dir,
      ch_genome,
      ch_fai
    )
    ch_qc = ch_qc.mix(HIC.out.qc)
  }

  multiqc(ch_qc.collect())
}
