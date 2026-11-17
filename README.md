# PlotTrellis-wf

A Nextflow pipeline that turns raw sequencing data (FASTQ files) into the files used by the [PlotTrellis](https://aleks-wehi.r-universe.dev/PlotTrellis) multi-omics dashboard, and writes a `samples.txt` that opens all of them in the app at once (see *Opening the results in the PlotTrellis app*). It runs on HPC clusters (SLURM, or PBS, LSF and SGE through profiles), and every tool runs in a container with a fixed version.

| Assay | `assay` value | Outputs |
|---|---|---|
| Bulk RNA-seq | `rna` | Salmon `quant.sf` per sample; mean TPM, bigWig coverage and splice-junction BED12 per group |
| ATAC-seq | `atac` | bigWig coverage and MACS3 peaks per group |
| ChIP-seq | `chip` | bigWig coverage and MACS3 peaks per group (controls are used for peak calling) |
| CUT&RUN | `cutrun` | as ChIP-seq |
| CUT&Tag | `cuttag` | as ChIP-seq |
| Hi-C (including Micro-C and Omni-C) | `hic` | `.hic` contact map per group |

---

## Quick start (for users)

**1. Fill in the samplesheet.** Download [`assets/samplesheet_template.xlsx`](assets/samplesheet_template.xlsx), replace the example rows with your samples and save it. The second sheet ("instructions") explains each column.

**2. Run**, from a terminal on your cluster's login node (SLURM):

```bash
module load apptainer nextflow       # module names vary between clusters; see "Requirements"
export NXF_VER=25.10.0               # the Nextflow version the pipeline was tested with
cd /path/to/my_experiment            # the folder with samples.xlsx; always start the run from here
sbatch -p long -t 14-00:00:00 -c 2 --mem 8G -J plottrellis -o nextflow_%j.log --wrap \
  "nextflow run plbaldoni/PlotTrellis-wf -resume --samplesheet samples.xlsx --outdir results --species mouse"
```

`sbatch` submits one small job that runs Nextflow for as long as the analysis takes, and Nextflow submits every analysis step as a job of its own. Give that job the longest time limit your cluster allows (`-p` and `-t`; here the `long` partition, 14 days). Useful commands:

| | |
|---|---|
| Is it running? | `squeue -u $USER` (the main job is called `plottrellis`) |
| Follow progress | `tail -f nextflow_<jobid>.log` |
| Cancel the run | `scancel <jobid>` (the main job; its analysis jobs stop too) |

If anything fails, fix the problem and **submit exactly the same command again from the same folder**. With `-resume`, finished steps are not redone. `-resume` continues the last run started from the folder, so use a separate folder for each analysis.

Before submitting anything, the pipeline checks the samplesheet and lists every problem it finds, such as a missing FASTQ file, a duplicated sample name or an unknown control.

Instead of `sbatch`, the `nextflow run ...` command can also be run on the login node inside `screen` or `tmux`, if your cluster allows long-running programs there; the run stops if that session is closed.

**Pipeline version.** Nextflow downloads the pipeline from GitHub on your first run and keeps using that copy for all your later runs; it does not update it by itself. To update to the newest version, run `nextflow pull plbaldoni/PlotTrellis-wf` once (later runs then use the new version), or add `-latest` to one `nextflow run` command. To use a given version, add `-r` and its release tag, e.g. `-r v1.0.0` (the versions are listed under *Releases* on the GitHub page). The version used is shown at the start of the Nextflow log.

---

## Samplesheet

Only the first sheet of the Excel file is read. One row per pair of FASTQ files (one FASTQ file for single-end data), or one row per GEO sample to download (see *Data from GEO*). Extra columns (cell type, colour, notes...) are allowed and ignored. Column names ignore case, and spaces count as `_` (`Biological replicate` works).

| Column | Required | Description |
|---|---|---|
| `sample` | yes | Sample name (letters, numbers, `.`, `_`, `-`; no spaces). Repeat it on several rows for technical replicates |
| `group` | yes | Samples with the same group and assay are combined into one coverage track and one set of peaks (Hi-C: one contact map) |
| `biological_replicate` | yes | Biological replicate number within the group (1, 2, ...) |
| `technical_replicate` | yes (column) | Technical replicate number within the sample (1, 2, ...), e.g. for a library sequenced on several lanes or runs. Can be left empty when a sample has a single row |
| `assay` | yes | `rna`, `atac`, `chip`, `cutrun`, `cuttag` or `hic` |
| `fastq_1` | yes (column) | Full path (starting with `/`) to the read 1 FASTQ. Leave empty only for a sample downloaded from GEO |
| `fastq_2` | yes (column) | Full path to the read 2 FASTQ. Leave the cell empty for single-end data |
| `control` | yes (column) | ChIP/CUT&RUN/CUT&Tag only: sample name(s) of the input/IgG control, separated by `;`. Leave empty otherwise |
| `peak_type` | no | `narrow` or `broad`. Empty uses `--peak-type` (default `narrow`). Must be the same within a group |
| `gsm` | no | GEO sample accession (e.g. `GSM7142991`). Used only when `fastq_1` and `fastq_2` are empty: the sample's data are then downloaded from SRA |
| `condition` | no | For the PlotTrellis app: the condition the group belongs to (e.g. a cell type or treatment). Empty means the group is its own condition. Must be the same within a group (see *Opening the results in the PlotTrellis app*) |
| `target` | no | ChIP/CUT&RUN/CUT&Tag only: the antibody target (e.g. `H3K27me3`, `CTCF`, `IgG`), used as the track name in the app. Empty means the assay name (`ChIP`, `CUT&RUN`, `CUT&Tag`). Must be the same within a group |

**Technical replicates.** Rows with the same sample name are technical replicates. Their FASTQ files are merged (read 1 with read 1, read 2 with read 2) before alignment and quantification, so they count as one sample. Number them in `technical_replicate`. FastQC runs on each technical replicate separately. For example, a library sequenced on two lanes:

| sample | group | biological_replicate | technical_replicate | assay | fastq_1 | fastq_2 |
|---|---|---|---|---|---|---|
| ATAC_CD8_N_1 | ATAC_CD8_N | 1 | 1 | atac | `/.../ATAC_4N1_L001_R1.fastq.gz` | `/.../ATAC_4N1_L001_R2.fastq.gz` |
| ATAC_CD8_N_1 | ATAC_CD8_N | 1 | 2 | atac | `/.../ATAC_4N1_L002_R1.fastq.gz` | `/.../ATAC_4N1_L002_R2.fastq.gz` |

**Data from GEO.** To process published data, put the GEO sample accession (`GSM...`) in the `gsm` column and leave `fastq_1` and `fastq_2` empty. The pipeline finds the sample's sequencing runs in SRA (through NCBI), downloads them and merges them, so each run is a technical replicate (leave `technical_replicate` empty; FastQC labels the runs `<sample>_T1`, `<sample>_T2`, ...). Paired-end or single-end is taken from SRA. Rows with FASTQ paths and rows with a GSM can be mixed in one samplesheet, and a row that has both uses its FASTQ files. The downloaded FASTQ files are kept in `<outdir>/fastq/` (one pair per SRA run, e.g. `SRR24064876_R1.fastq.gz`), and later runs with the same output folder use them instead of downloading again; `--keep-downloads false` leaves them in the scratch work folder only.

| sample | group | biological_replicate | technical_replicate | assay | fastq_1 | fastq_2 | control | gsm |
|---|---|---|---|---|---|---|---|---|
| Ba_HiC_1 | Ba_HiC | 1 | | hic | | | | GSM7142991 |
| Ba_HiC_2 | Ba_HiC | 2 | | hic | | | | GSM7142992 |

Rules checked by the pipeline:
- Technical replicates of a sample have different `technical_replicate` numbers and the same group, biological replicate, assay, control, peak type and read layout. Their FASTQ files are all compressed (`.gz`) or all uncompressed.
- Different samples in a group have different biological replicate numbers.
- A FASTQ file is used only once, and so is a GSM.
- A sample downloaded from GEO has a single row. Its GSM must exist in SRA, have runs of a single read layout, and come from the species given by `--species`.
- Every sample in a group must be paired-end, or every sample must be single-end. Hi-C samples must be paired-end.
- Controls go in their own group, have the same assay as the samples that use them, and have no control of their own.
- Controls get a coverage track, but no peaks.
- `condition` and `target` may contain letters, numbers, spaces and `. _ - & + ( )`. Two groups of one condition cannot give the same app track (e.g. two RNA-seq groups, or two ChIP-seq groups with the same target).

---

## Options

Pipeline options start with two hyphens and go at the end of the `nextflow run` command. Options with one hyphen belong to Nextflow itself: `-resume` (continue a run), `-r` and `-latest` (pipeline version, see *Pipeline version*), `-profile` (see *Requirements and running elsewhere*), `-work-dir` (work folder) and `-c` (extra config file).

| Option | Default | Description |
|---|---|---|
| `--samplesheet` | required | Samplesheet (`.xlsx`; `.csv` also accepted) |
| `--outdir` | required | Results folder |
| `--species` | required | `human` (GRCh38) or `mouse` (GRCm39) |
| `--assay` | all in samplesheet | Comma-separated subset, e.g. `rna,atac` |
| `--keep-downloads` | `true` | Keep the FASTQ files downloaded from GEO in `<outdir>/fastq/`. `--keep-downloads false` leaves them in the scratch work folder only |
| `--trim` | off | Trim reads with fastp before alignment and quantification. On its own it applies to every assay, or give a comma-separated list of assays, e.g. `--trim atac,cuttag`. Settings are under *What the pipeline does*. Recommended for NextSeq/NovaSeq data with many adapter dimers or poly-G reads, which can make alignment very slow |
| `--trim-args` | none | Extra options added to every `fastp` call, e.g. `--trim-args "--length_required 20"` |
| `--gencode` | `latest` | GENCODE release, e.g. `50` (human) or `M39` (mouse). The same release is used for every assay |
| `--blacklist` | off | Remove reads in blacklisted regions before peak calling and coverage (DNA assays). Without a value, uses the [excluderanges](https://github.com/dozmorovlab/excluderanges) sets included in [`assets/blacklists`](assets/blacklists) (`hg38.Kundaje.GRCh38_unified_Excludable` / `mm39.excluderanges`); or give the path to your own BED file |
| `--peak-type` | `narrow` | Default MACS3 peak type |
| `--normalize-with-autosome` | off | Compute coverage normalisation factors from autosomes only (chr1–22 human, chr1–19 mouse). All chromosomes still appear in the tracks |
| `--salmon-gibbs` | `100` | Number of Salmon Gibbs samples |
| `--effective-genome-size` | species default | Effective genome size for RPGC and MACS3 |
| `--macs3-args` | none | Extra options added to every `macs3 callpeak` call |
| `--hic-dedup` | `true` | Hi-C: remove duplicate read pairs. `--hic-dedup false` keeps them |
| `--pairtools-parse-args` | none | Hi-C: extra options added to every `pairtools parse` call, e.g. `--pairtools-parse-args "--min-mapq 30"` |
| `--pairtools-select` | none | Hi-C: [`pairtools select`](https://pairtools.readthedocs.io/en/latest/cli_tools.html#pairtools-select) condition applied to each group's pairs before the contact map is made, e.g. `--pairtools-select '(chrom1 != chrom2) or (abs(pos1 - pos2) > 1000)'` to remove contacts closer than 1 kb |
| `--juicer-pre-args` | none | Hi-C: extra options added to every `juicer_tools pre` call, e.g. `--juicer-pre-args "-r 1000000,100000,10000,5000"` for a subset of resolutions |
| `--scratch` | see *The scratch folder* | Folder for the work files, references and containers |
| `--ref-dir` | `<scratch>/references` | Folder where the GENCODE files and indexes are stored and reused (see *Reusing references and indexes*) |
| `--minimap2-index-dna` | built | Pre-built minimap2 index (`-x sr`) |
| `--minimap2-index-rna` | built | Pre-built minimap2 index (`-x splice:sr`) |
| `--salmon-index` | built | Pre-built decoy-aware Salmon index (made with Salmon 2.x; 1.x indexes are not compatible) |
| `--bwa-index` | built | Pre-built bwa index (Hi-C): the folder that holds the index files (`.amb`, `.ann`, `.bwt`, `.pac`, `.sa`) |
| `--partition` | scheduler default | SLURM partition (or queue, with another scheduler) for the analysis jobs. The longest jobs ask for 48 hours, so the partition's time limit must be at least that |
| `--max-cpus` | `56` | No job asks for more CPUs than this. Lower it if the cluster's nodes are smaller |
| `--max-memory` | `480.GB` | No job asks for more memory than this, e.g. `--max-memory 250.GB` |
| `--max-time` | `14.d` | No job asks for a longer time limit than this, e.g. `--max-time 2.d` |

Pre-built indexes must come from the same GENCODE genome and release as `--gencode`.

### Reusing references and indexes

The first run for a species and GENCODE release downloads the GENCODE files and builds the indexes it needs into `<ref-dir>/<species>/gencode_<release>/`, e.g. `<scratch>/references/mouse/gencode_M39/`. They stay there after the run, and any later run with the same folder, species and release uses them instead of downloading and building them again. A later run that needs another index (e.g. the Salmon index the first time RNA-seq is run) adds it to the same folder. To make sure a run reuses them:

- Use the same scratch folder (or `--ref-dir`) as the earlier run. Setting `PLOTTRELLIS_SCRATCH` once (see *The scratch folder*) does this for every run.
- Give the release explicitly, e.g. `--gencode M39` (the release is shown at the start of every run and in `logs/pipeline_info/references.txt`). With the default `--gencode latest`, a run made after GENCODE publishes a new release downloads and builds that release instead.

Scratch folders are often cleaned automatically. To keep references for longer, store them on permanent storage with `--ref-dir /path/to/references`; anything missing from the folder is downloaded or rebuilt by the next run. Indexes stored elsewhere can also be given one by one with `--minimap2-index-dna`, `--minimap2-index-rna`, `--salmon-index` and `--bwa-index`.

---

## Requirements and running elsewhere

The pipeline needs:

- **Nextflow 25.10 or later** (with Java 17 or later). Most clusters have a `nextflow` module (`module avail nextflow`). Otherwise, install it once without admin rights with `curl -s https://get.nextflow.io | bash`, which creates a `nextflow` file to move into a folder on your `PATH` (e.g. `~/bin`). `export NXF_VER=25.10.0` makes any Nextflow installation run version 25.10.0, the version the pipeline was tested with.
- **Apptainer** (or Singularity, with `-profile singularity`), to run the containers. On clusters with environment modules, load it before Nextflow (`module load apptainer nextflow`), because some Nextflow modules load their own Apptainer otherwise.
- **A job scheduler**: SLURM by default; PBS, LSF and SGE through profiles (see *Other schedulers*).
- Internet access on the compute nodes, to download the containers, the GENCODE files and data from GEO.

The pipeline uses Apptainer even when a personal or site-wide Nextflow configuration (such as `~/.nextflow/config`) turns Singularity on. To use Singularity instead, add `-profile singularity`.

### The scratch folder

Large files that can be made again go into a scratch folder rather than the results folder: the Nextflow work files (BAM files, Hi-C pairs, merged and trimmed FASTQ files; often hundreds of GB per run), the GENCODE files and indexes (`references/`, about 40 GB per species) and the containers (`containers/`, about 2 GB). The work files are needed only to resume a run; the references and containers are reused by later runs. The folder is, in this order:

1. `--scratch /path/to/folder`, if given;
2. the `PLOTTRELLIS_SCRATCH` environment variable, if set;
3. `/vast/scratch/users/$USER/plottrellis`, if `/vast/scratch/users/$USER` exists;
4. otherwise `plottrellis_scratch` in the folder the run is started from.

With the last option, every project folder gets its own copy of the references and containers. To share them between projects, choose a scratch folder once, e.g. by adding `export PLOTTRELLIS_SCRATCH=/path/to/scratch/plottrellis` to `~/.bashrc`. The work files go into `<scratch>/work` unless Nextflow's `-work-dir` option is given.

### Other schedulers

On clusters with PBS Pro, PBS/Torque, LSF or SGE, add the profile of the scheduler, and submit the main Nextflow job with that scheduler's command (`qsub`, `bsub`) instead of `sbatch`, or run it on a login node inside `screen` or `tmux`. The main job needs 2 CPUs and 8 GB of memory for as long as the run takes:

```bash
nextflow run plbaldoni/PlotTrellis-wf -resume -profile pbspro \
  --samplesheet samples.xlsx --outdir results --species mouse --partition workq
```

The largest jobs ask for 32 CPUs and up to 96 GB of memory (after retries), and DNA alignment can take up to 48 hours; use `--max-cpus`, `--max-memory` and `--max-time` to fit them to the cluster. Settings specific to a site (e.g. a project or account to charge) go in a small config file given with `-c`:

```groovy
// site.config
process.clusterOptions = '-P myproject'     // project to charge (-P for PBS Pro, LSF and SGE; some sites use -A)
process.penv           = 'smp'              // SGE only: the parallel environment for multi-CPU jobs ('qconf -spl' lists them)
executor.perJobMemLimit = true              // LSF only, if the cluster limits memory per job rather than per CPU
```

Use `-c` only with Nextflow's default syntax parser: with `NXF_SYNTAX_PARSER=v2`, Nextflow 25.10 does not find the pipeline's profiles when a `-c` file is given.

| Profile | Effect |
|---|---|
| *(none)* | Apptainer containers, SLURM jobs |
| `pbspro` / `pbs` | PBS Pro / PBS (Torque) jobs |
| `lsf` | LSF jobs |
| `sge` | SGE, UGE or Altair Grid Engine jobs (parallel environment `smp`) |
| `singularity` | Singularity instead of Apptainer |
| `docker` / `podman` | Docker or Podman instead of Apptainer |
| `local` | Run every step on the current node instead of submitting jobs |

Profiles combine with a comma, e.g. `-profile lsf,singularity`.

---

## Outputs

```
<outdir>/
├── rna/
│   ├── quantification/<sample>/quant.sf   Salmon output (plus Gibbs samples, logs)
│   ├── quantification_mean/<group>/quant.sf   mean TPM of the group's samples (columns Name, TPM)
│   ├── coverage/<group>.bw                CPM bigWig
│   └── junctions/<group>.junctions.bed    splice junctions, BED12
├── atac/ | chip/ | cutrun/ | cuttag/
│   ├── coverage/<group>.bw                RPGC bigWig (controls included)
│   └── peaks/<group>_peaks.narrowPeak     or .broadPeak
├── hic/
│   └── contacts/<group>.hic               contact map (normalisations: VC, VC_SQRT, KR, SCALE)
├── reference/                             GENCODE annotation used by the run (.gtf.gz, for the app)
├── samples.txt                            the samples file of the PlotTrellis app (see below)
├── fastq/                                 FASTQ files downloaded from GEO (one pair per SRA run; see --keep-downloads)
├── qc/
│   ├── multiqc_report.html                one report for all assays
│   ├── fastqc/
│   └── fastp/                             with --trim: fastp report per sample
└── logs/
    ├── nextflow_<date>_<time>.log         Nextflow's log of each run (copied from .nextflow.log in the launch folder)
    ├── pipeline_info/                     report, timeline, trace, validated samplesheet, references used
    └── tasks/                             command, output and error files of every step
```

BAM files, Hi-C pairs files and trimmed FASTQ files are not kept in the results. They stay in the Nextflow work folder in the scratch folder (see *The scratch folder*).

### Opening the results in the PlotTrellis app

After a successful run, the pipeline writes `samples.txt` at the top of the output folder. Open it in the PlotTrellis app to see all results at once. It has one row per condition (the samplesheet's `condition`, or the group name when that is empty) and one column per track, with paths relative to the output folder, so the folder can be moved or copied as a whole. It also names the GENCODE annotation in `reference/` and the genome (`mm39` or `hg38`). The colours are left to the app.

The app is an R package, available from [R-universe](https://aleks-wehi.r-universe.dev/PlotTrellis), where its guide is also found. Install it once in R:

```r
install.packages("BiocManager")
install.packages("PlotTrellis", repos = c("https://aleks-wehi.r-universe.dev", BiocManager::repositories()))
```

Then open the results with a new, empty project folder of your own:

```r
PlotTrellis::run_plottrellis(project_dir = "my-project", samples_txt = "/path/to/results/samples.txt")
```

The app keeps its settings, a copy of the samples file and its cache in `project_dir`, so use a folder outside the results folder. The result files themselves are read where they are.

| Assay | Tracks (`type:name`) |
|---|---|
| RNA-seq | `bw:RNA` (coverage), `paired-end:junctions` (splice junctions), `quantdir:salmon` (mean TPM of the group, `rna/quantification_mean/<group>/`) |
| ATAC-seq | `bw:ATAC`, `bed:ATAC_peaks` |
| ChIP-seq, CUT&RUN, CUT&Tag | `bw:<target>`, `bed:<target>_peaks` (controls: coverage only) |
| Hi-C | `hic:HiC` |

The app compares conditions on tracks of the same name, so give the same `target` to the same antibody in every condition. `samples.txt` lists every group of the samplesheet whose files are in the output folder, whatever `--assay` selects: runs of different assays into the same output folder build up one `samples.txt`.

Example: Basal and LP cells with RNA-seq, ATAC-seq, CUT&Tag (H3K36me3 with an IgG control) and Hi-C in each.

| sample | group | assay | control | condition | target |
|---|---|---|---|---|---|
| Ba_RNA_1 | Ba_RNA | rna | | Basal | |
| Ba_ATAC_1 | Ba_ATAC | atac | | Basal | |
| Ba_K36_1 | Ba_K36 | cuttag | Ba_IgG_1 | Basal | H3K36me3 |
| Ba_IgG_1 | Ba_IgG | cuttag | | Basal | IgG |
| Ba_HiC_1 | Ba_HiC | hic | | Basal | |
| LP_RNA_1 | LP_RNA | rna | | LP | |
| ... | | | | LP | |

gives

```
# data_root: .
# gtf_path: reference/gencode.vM39.primary_assembly.annotation.gtf.gz
# orgdb: org.Mm.eg.db
# genome_label: mm39
condition  colour  bw:RNA  paired-end:junctions  quantdir:salmon  bw:ATAC  bed:ATAC_peaks  bw:H3K36me3  bed:H3K36me3_peaks  bw:IgG  hic:HiC
Basal              rna/coverage/Ba_RNA.bw  rna/junctions/Ba_RNA.junctions.bed  rna/quantification_mean/Ba_RNA  atac/coverage/Ba_ATAC.bw  ...
LP                 rna/coverage/LP_RNA.bw  ...
```

---

## What the pipeline does

The pipeline changes the data as little as possible. Each tool runs with its own defaults unless stated below. Each group's merging, coverage and peak calling start as soon as that group's own samples are ready.

**References.** GENCODE primary-assembly genome, comprehensive primary-assembly ("PRI") GTF and transcript sequences, downloaded by Nextflow on the first run. They are stored, together with all indexes, in `<ref-dir>/<species>/gencode_<release>/` and reused by later runs (see *Reusing references and indexes*).

**Downloads from GEO** (samplesheet rows with a GSM and no FASTQ files). At the start, NCBI E-utilities give each GSM's SRA runs, read layout and organism (`esearch` and `efetch` in the `sra` database). Each run is then downloaded from NCBI's [SRA bucket on AWS](https://registry.opendata.aws/ncbi-sra/) (or with sra-tools `prefetch` if it is not there), checked with `vdb-validate`, and converted with `fasterq-dump --split-3`, which, for paired-end runs, leaves out reads whose mate is missing. NCBI allows 3 lookups per second; with many samples, an [NCBI API key](https://ncbiinsights.ncbi.nlm.nih.gov/2017/11/02/new-api-keys-for-the-e-utilities/) in the `NCBI_API_KEY` environment variable allows 10.

Before anything else, FastQC runs on every technical replicate, and the FASTQ files of each sample's technical replicates are merged (`cat`).

**Read trimming** (only with `--trim`). fastp runs on each sample after merging, with its defaults (adapter trimming by read-pair overlap; reads with more than 40% of bases below Q15, more than 5 N bases or shorter than 15 bp are removed, and a pair is removed when either read fails) plus two options:
- `--trim_poly_g`: trims poly-G tails, which two-colour instruments (NextSeq, NovaSeq) produce when there is no signal. fastp only does this by itself when the read names contain the instrument ID, which is often not the case (e.g. data downloaded from SRA).
- `--detect_adapter_for_pe` (paired-end): also looks for the adapter sequence, which catches adapter dimers that read-pair overlap misses. fastp always does this for single-end reads.

Untrimmed adapter dimers with poly-G reads can make minimap2 `-x sr` alignment many times slower (see [minimap2 issue #1180](https://github.com/lh3/minimap2/issues/1180)).

**RNA-seq**
1. Salmon `quant -l A --numGibbsSamples 100` against a decoy-aware index (whole genome as decoys, built with `--gencode`, so transcript IDs keep their version suffix).
   Each transcript's TPM is then averaged over the samples of a group (arithmetic mean, every sample weighted equally) and written to `quantification_mean/<group>/quant.sf` with the columns `Name` and `TPM`, in Salmon's transcript order. A group with one sample gets that sample's TPM.
2. minimap2 two-pass spliced alignment (`-x splice:sr -j <GENCODE BED12>`, then `--pass1`). Only unmapped reads are removed (paired-end: both mates must be mapped).
3. Samples of a group are merged (`samtools merge`). Coverage comes from `bamCoverage --normalizeUsing CPM --binSize 10`, unstranded, using all alignments.
4. Splice junctions come from minimap2's pass-1 `--write-junc` output. Each junction is counted once per fragment (paired-end) or once per read (single-end), and counts are summed within the group. The output is BED12 with two 1-bp blocks flanking the intron, and the score is the number of supporting fragments. `--write-junc` only reports primary alignments with MAPQ ≥ 10.

**ATAC-seq, ChIP-seq, CUT&RUN, CUT&Tag**
1. minimap2 `-ax sr` (32 threads). Only unmapped reads are removed (paired-end: both mates must be mapped). Duplicates are kept, and there is no MAPQ filter.
2. Optional blacklist filtering (`--blacklist`).
3. Samples of a group are merged. Coverage comes from `bamCoverage --normalizeUsing RPGC --binSize 10`, using all alignments.
4. MACS3 `callpeak` on the merged group BAM: `-f BAMPE` for paired-end (including ATAC), `-f BAM` for single-end, with the group's control samples as `-c`, and `--broad` when the peak type is broad. All other MACS3 settings, including `--keep-dup`, are left at their defaults.

**Hi-C**
1. bwa `mem -SP` (32 threads), which aligns the two reads of a pair independently, without mate rescue or pairing, as [pairtools recommends](https://pairtools.readthedocs.io/en/latest/parsing.html). The bwa index is built from the GENCODE genome.
2. `pairtools parse` with its defaults (`--min-mapq 1`, `--walks-policy 5unique`), then `pairtools sort`.
3. `pairtools dedup` with its defaults: a pair is a duplicate when both of its ends are within 3 bp of another pair's. Only pairs with both sides mapped are kept. Unlike the other assays, duplicates are removed by default: each pixel of a contact map comes from few molecules, so PCR copies of one ligation product look like strong contacts. Because both ends must match, few independent pairs are flagged by chance. `--hic-dedup false` keeps them.
4. The pairs of a group's samples are merged (`pairtools merge`), and `juicer_tools pre` makes the `.hic` file at Juicer's default resolutions (2.5 Mb to 1 kb) with the VC, VC_SQRT, KR and SCALE normalisations. Juicer Tools 2 no longer computes KR by default, but it is added because the PlotTrellis app uses KR by default.

No restriction-enzyme information is needed, so the same steps work for Hi-C with any enzyme, Micro-C and Omni-C. `--blacklist` and `--normalize-with-autosome` do not apply to Hi-C.

**Effective genome size** (RPGC and MACS3 `-g`): the deepTools "non-N bases" values, which deepTools recommends when multimapping reads are kept: GRCh38 3,130,250,755; GRCm39 2,654,621,783.

---

## For maintainers

```
main.nf                 entry workflow: option checks, samplesheet, references, QC
workflows/rnaseq.nf     RNA-seq steps
workflows/dnaseq.nf     ATAC/ChIP/CUT&RUN/CUT&Tag steps
workflows/hic.nf        Hi-C steps
modules/*.nf            one process per file
lib/Samplesheet.groovy  .xlsx/.csv reader and validation
lib/GeoSamples.groovy   GEO sample (GSM) to SRA run lookup with NCBI E-utilities
lib/GenomeRefs.groovy   GENCODE URLs, blacklists, genome constants
lib/Flags.groovy        reads on/off options the same way under both Nextflow syntax parsers
assets/blacklists/      default blacklists (BED) and their provenance
nextflow.config         parameters, schedulers (SLURM by default), Apptainer, logging
```

**Dry run.** `-stub-run` runs the whole workflow with placeholder commands. It checks the samplesheet, the channel wiring and the output layout in a few minutes:

```bash
nextflow run . -stub-run -profile local --samplesheet samples.xlsx --outdir /tmp/test --species mouse
```

**Local copy.** To run a local copy of the pipeline (e.g. to test changes before they are pushed), give its folder instead of `plbaldoni/PlotTrellis-wf`: `nextflow run /path/to/PlotTrellis-wf -resume ...`.

**Resources.** Each process sets its own `cpus`, `memory` and `time`. Memory defaults come from the peak memory of a full-size mouse run, with headroom. A task that fails for lack of memory or time (exit codes 104, 134, 137, 139, 140, 143, 247) is retried up to twice, with its memory multiplied by the attempt number.

**Containers** (pinned):

| Tool | Image |
|---|---|
| minimap2 2.31 | `quay.io/biocontainers/minimap2:2.31--h118bc1c_0` |
| minimap2 2.31 + samtools 1.23.1 | `quay.io/biocontainers/mulled-v2-66534bcbb7031a148b13e2ad42583020b9cd25c4:b411340b52d82a9c276d87c7a3dcffc880be762f-0` |
| samtools 1.23.1 | `quay.io/biocontainers/samtools:1.23.1--ha83d96e_0` |
| Salmon 2.8.0 | `quay.io/biocontainers/salmon:2.8.0--hfa8f182_0` |
| deepTools 3.5.6 | `quay.io/biocontainers/deeptools:3.5.6--pyhdfd78af_0` |
| MACS3 3.0.5 | `quay.io/biocontainers/macs3:3.0.5--py312h9639c01_0` |
| fastp 1.4.0 | `quay.io/biocontainers/fastp:1.4.0--h43da1c4_0` |
| bwa 0.7.19 + samtools 1.22.1 | `quay.io/biocontainers/mulled-v2-fe8faa35dbf6dc65a0f7f5d4ea12e31a79f73e40:f45ad9036aa41bb10f875a330fa877d8869018a1-0` |
| pairtools 1.1.3 | `quay.io/biocontainers/pairtools:1.1.3--py312h5219090_0` |
| Juicer Tools 2.20.00 | `quay.io/biocontainers/juicertools:2.20.00--hdfd78af_0` |
| sra-tools 3.0.8 + pigz 2.6 | `quay.io/biocontainers/mulled-v2-5f89fe0cd045cb1d615630b9261a1d17943a9b6a:2f4a4c900edd6801ff0068c2b3048b4459d119eb-0` |
| FastQC 0.12.1 | `quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0` |
| MultiQC 1.35 | `quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2` |
