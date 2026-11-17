# Changelog

All notable changes to PlotTrellis-wf are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). A summary for users is in `NEWS.md`.

## [1.0.1] - 2026-11-17

### Changed

- The minimum Nextflow version is now 25.04.0 (was 25.10.0). The pipeline was stub-tested with
  Nextflow 25.04.2 (default syntax parser), 25.10.0 and 26.04.3 (both parsers); the newer syntax
  parser (`NXF_SYNTAX_PARSER=v2`) needs 25.10 or later.
- An older Nextflow now stops at once with "Nextflow version ... does not match workflow
  required version: >=25.04.0" (`manifest.nextflowVersion = '!>=25.04.0'`). Before, Nextflow
  24.10 and older stopped with a script compilation error in `main.nf` instead, caused by the
  `try`/`catch` around the `--gencode` check; that check now uses
  `GenomeRefs.resolveReleaseOrError()` and gives the same messages.
- The README's Quick start no longer sets `NXF_VER`, so any installed Nextflow from 25.04 on is
  used. *Requirements* explains how to load a newer module or set `NXF_VER` when the default
  Nextflow is older.

## [1.0.0] - 2026-11-17

First release.

### Added

- **Assays**: bulk RNA-seq (`rna`), ATAC-seq (`atac`), ChIP-seq (`chip`), CUT&RUN (`cutrun`),
  CUT&Tag (`cuttag`) and Hi-C (`hic`, enzyme-agnostic, so Micro-C and Omni-C too). `--assay`
  selects a subset of the samplesheet.
- **Species and references**: human (GRCh38) and mouse (GRCm39, GENCODE M26 or later), GENCODE
  primary-assembly annotation. `--gencode` (default `latest`) picks the release. Genome, GTF,
  transcripts and indexes (minimap2 DNA and RNA, decoy-aware Salmon, bwa) are downloaded or built
  once into `<ref-dir>/<species>/gencode_<release>/` and reused; `--minimap2-index-dna`,
  `--minimap2-index-rna`, `--salmon-index` and `--bwa-index` take existing ones.
- **Samplesheet** (`.xlsx` or `.csv`, template in `assets/samplesheet_template.xlsx`): columns
  `sample`, `group`, `biological_replicate`, `technical_replicate`, `assay`, `fastq_1`, `fastq_2`,
  `control`, and the optional `peak_type`, `gsm`, `condition` and `target`. Single-end reads are
  detected from an empty `fastq_2`; technical replicates are concatenated; controls are referenced
  by sample name (several separated by `;`). All errors are collected and reported together.
- **GEO downloads**: rows with a `gsm` and no FASTQ paths are looked up in SRA (NCBI E-utilities;
  `NCBI_API_KEY` is used if set) and downloaded from the SRA bucket on AWS, with `prefetch` as the
  fallback. Each SRA run becomes a technical replicate. `--keep-downloads` (default on) keeps the
  FASTQ files in `<outdir>/fastq/` for later runs.
- **Read trimming** (opt-in): `--trim` or `--trim <assays>` runs fastp with its defaults plus
  poly-G trimming and paired-end adapter detection; `--trim-args` passes extra options.
- **RNA-seq**: Salmon quantification (`-l A`, 100 Gibbs samples, `--salmon-gibbs`); the group's
  mean TPM as a two-column `quant.sf` (`rna/quantification_mean/<group>/`); two-pass minimap2
  `splice:sr` alignment guided by the annotation; CPM bigWig coverage of the merged group; splice
  junctions counted once per fragment, summed per group, as BED12.
- **ATAC-seq, ChIP-seq, CUT&RUN, CUT&Tag**: minimap2 `sr` alignment; RPGC bigWig coverage per
  group (controls included); MACS3 peaks per treatment group with the group's controls, narrow by
  default (`--peak-type`, or the samplesheet's `peak_type` per group); `--macs3-args`.
  `--blacklist` (off by default) removes reads in the bundled excluderanges regions or a given
  BED; `--effective-genome-size` overrides the deepTools non-N genome sizes.
- **Hi-C**: `bwa mem -SP`; `pairtools parse`, `sort`, `dedup` (on by default, `--hic-dedup`) and
  `merge`; `juicer_tools pre` writing a `.hic` file with VC, VC_SQRT, KR and SCALE normalisations
  at Juicer's default resolutions (2.5 Mb to 1 kb). `--pairtools-parse-args`,
  `--pairtools-select` and `--juicer-pre-args` pass extra options.
- **Quality control**: FastQC per technical replicate and one MultiQC report covering FastQC,
  fastp, samtools stats and flagstat, Salmon, MACS3 and pairtools.
- **PlotTrellis app files**: `<outdir>/samples.txt`, written after a successful run, with one row
  per condition and one column per track (`bw`, `bed`, `paired-end`, `quantdir`, `hic`), paths
  relative to the output folder; the GENCODE GTF, bgzipped, in `<outdir>/reference/`.
- **Execution**: SLURM by default (`--partition`); profiles `pbspro`, `pbs`, `lsf`, `sge`,
  `local`, `singularity`, `docker` and `podman`; `--max-cpus`, `--max-memory` and `--max-time`
  cap the resources of every task. Pinned containers from quay.io/biocontainers. Work files,
  references and container images go to a scratch folder (`--scratch`, `PLOTTRELLIS_SCRATCH`).
  Retries with more memory on out-of-memory and time-limit exits.
- **Logs**: the Nextflow log, report, timeline, trace, validated samplesheet and references used
  in `<outdir>/logs/`, plus every task's log in `<outdir>/logs/tasks/`.
- Runs under both Nextflow syntax parsers (v1 and `NXF_SYNTAX_PARSER=v2`); Nextflow 25.10.0 or
  later (lowered to 25.04.0 in 1.0.1).

### Tool versions

minimap2 2.31, samtools 1.23.1, Salmon 2.8.0, deepTools 3.5.6, MACS3 3.0.5, fastp 1.4.0,
FastQC 0.12.1, MultiQC 1.35, bwa 0.7.19, pairtools 1.1.3, Juicer Tools 2.20.00, sra-tools 3.0.8.

[1.0.1]: https://github.com/plbaldoni/PlotTrellis-wf/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/plbaldoni/PlotTrellis-wf/releases/tag/v1.0.0
