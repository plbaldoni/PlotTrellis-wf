# Blacklists

Default blacklists used with `--blacklist` (BED3, 0-based starts, UCSC chromosome names).

| File | Genome | Regions | Source |
|---|---|---|---|
| `hg38.Kundaje.GRCh38_unified_Excludable.bed` | GRCh38 | 910 | excluderanges `hg38.Kundaje.GRCh38_unified_Excludable.rds` (md5 `654e22c08a65a7fff16337cfc406dd2b`) |
| `mm39.excluderanges.bed` | GRCm39 | 3147 | excluderanges `mm39.excluderanges.rds` (md5 `31fb7836575fd41f4f5e213f2fbebf1e`) |

The `.rds` files (GenomicRanges objects) come from the [excluderanges](https://github.com/dozmorovlab/excluderanges) Zenodo record [21480958](https://zenodo.org/records/21480958). They were converted with:

```r
library(GenomicRanges)
gr <- sort(sortSeqlevels(readRDS("<name>.rds")))
bed <- data.frame(as.character(seqnames(gr)), start(gr) - 1L, end(gr))
write.table(bed, "<name>.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
```
