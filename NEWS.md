# PlotTrellis-wf 1.0.1

- Works with Nextflow 25.04 or later (1.0.0 needed 25.10). Any Nextflow from 25.04 on can be
  used; the Quick start no longer asks for a particular version. Nextflow's newer syntax parser
  (`NXF_SYNTAX_PARSER=v2`) still needs 25.10 or later.

# PlotTrellis-wf 1.0.0

First release. PlotTrellis-wf turns raw sequencing data (FASTQ files) into the files read by the
PlotTrellis app, and writes a `samples.txt` that opens all of them in the app at once.

## What it does

- Processes bulk RNA-seq, ATAC-seq, ChIP-seq, CUT&RUN, CUT&Tag and Hi-C (including Micro-C and
  Omni-C) for human (GRCh38) and mouse (GRCm39), with GENCODE annotation.
- One Excel (or CSV) samplesheet describes every sample, whatever the assay. `--assay` runs a
  subset. Technical replicates (several FASTQ pairs of one sample) are merged, and controls are
  named per sample for ChIP-seq, CUT&RUN and CUT&Tag. Every problem in the samplesheet is listed
  in plain English before anything is submitted.
- Published data can be used directly: put a GEO sample accession (`GSM...`) in the `gsm` column
  and the pipeline downloads its sequencing runs from SRA.
- Results are per group of replicates:
  - RNA-seq: Salmon `quant.sf` per sample, the group's mean TPM, bigWig coverage and splice
    junctions;
  - ATAC-seq, ChIP-seq, CUT&RUN and CUT&Tag: bigWig coverage and MACS3 peaks;
  - Hi-C: a `.hic` contact map with KR normalisation at every resolution down to 1 kb;
  - quality control: FastQC and one combined MultiQC report.
- The GENCODE files and indexes are downloaded and built on the first run, then reused by later
  runs. The GENCODE annotation is also copied into the results for the app.
- Tools run with their defaults, without extra filtering: no MAPQ filter and no duplicate
  removal (except for Hi-C, where duplicate pairs are removed). Read trimming (`--trim`),
  blacklist filtering (`--blacklist`) and normalisation on autosomes only
  (`--normalize-with-autosome`) are opt-in.
- Runs on SLURM out of the box; PBS Pro, PBS, LSF and SGE through profiles. Every tool runs in a
  container with a fixed version (Apptainer by default; Singularity, Docker and Podman through
  profiles).

## Using the results in the PlotTrellis app

- After a successful run, `<outdir>/samples.txt` lists every result as a track: one row per
  condition and one column per track. The new optional samplesheet columns `condition` (which
  groups belong together in the app) and `target` (the antibody, which names the ChIP-seq,
  CUT&RUN and CUT&Tag tracks) control the layout. Paths are relative, so the output folder can
  be moved or copied as a whole.
- Runs of different assays into the same output folder build up one `samples.txt`.
