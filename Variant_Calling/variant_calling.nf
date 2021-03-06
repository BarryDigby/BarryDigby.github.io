#!/usr/bin/env nextflow

/*
 Parameters
*/

/*
 Sequencing Reads
*/

params.reads = "/data/bdigby/WES/MA5112/reads/*_r{1,2}.fastq.gz"
Channel
	.fromFilePairs(params.reads)
	.set{reads_ch}

/*
 Reference Genome Files (pass --analysisDir via command line)
*/

params.fasta = Channel.fromPath("$params.analysisDir/reference/*fasta").getVal()
params.fai = Channel.fromPath("$params.analysisDir/reference/*.fasta.fai").getVal()
params.dict = Channel.fromPath("$params.analysisDir/reference/*.dict").getVal()

params.amb = Channel.fromPath("$params.analysisDir/reference/*fasta.amb").getVal()
params.ann = Channel.fromPath("$params.analysisDir/reference/*fasta.ann").getVal()
params.bwt = Channel.fromPath("$params.analysisDir/reference/*fasta.bwt").getVal()
params.pac = Channel.fromPath("$params.analysisDir/reference/*fasta.pac").getVal()
params.sa = Channel.fromPath("$params.analysisDir/reference/*fasta.sa").getVal()

/*
 Exome Intervals, dbSNP, Mills_KG
*/

params.intlist = Channel.fromPath("$params.analysisDir/assets/*bed.interval_list").getVal()
params.dbsnp = Channel.fromPath("$params.analysisDir/assets/dbsnp*.gz").getVal()
params.dbsnptbi = Channel.fromPath("$params.analysisDir/assets/dbsnp*.tbi").getVal()
params.mills = Channel.fromPath("$params.analysisDir/assets/Mills_KG*.gz").getVal()
params.millstbi = Channel.fromPath("$params.analysisDir/assets/Mills_KG*.gz.tbi").getVal()

/*
 snpEFF Cache
*/

params.snpeff_cache = "/data/snpEff"
params.snpeff_db = "GRCh37.75"

/*
 Write Directory (pass --outDir via command line)
*/

params.outDir = ""
params.analysisDir = ""
/*
================================================================================
                                  ALIGNMENT
================================================================================
*/

process MapReads{
        
	publishDir path: "$params.outDir/analysis/bwa_aln", mode: "copy"
	
        input:
        tuple val(base), file(reads) from reads_ch
        val(fasta) from params.fasta
        tuple file(amb), file(ann), file(bwt), file(pac), file(sa) from Channel.value([params.amb, params.ann, params.bwt, params.pac, params.sa])
        
        output:
        tuple val(base), file("${base}.bam") into bamMapped
	tuple val(base), file("${base}.bam") into bamMappedBamQC

        script:
	readGroup = "@RG\\tID:sample_1\\tLB:sample_1\\tPL:ILLUMINA\\tPM:HISEQ\\tSM:sample_1"
        """
        bwa mem \
	-K 100000000 \
	-R \"${readGroup}\" \
	-t 8 \
	$fasta \
	$reads | samtools sort - > ${base}.bam
        """
}


/*
================================================================================
                                 PROCESSING
================================================================================
*/


process MarkDuplicates{

	publishDir path: "$params.outDir/analysis/mark_dups", mode: "copy"

	input:
	tuple val(base), file(bam) from bamMapped

	output:
	tuple val(base), file("${base}.md.bam"), file("${base}.md.bam.bai") into bam_duplicates_marked
	file("${base}.bam.metrics") into duplicates_marked_report
	
	script:
	"""
	gatk --java-options -Xmx8g \
        MarkDuplicates \
        --MAX_RECORDS_IN_RAM 50000 \
        --INPUT $bam \
        --METRICS_FILE ${base}.bam.metrics \
        --TMP_DIR . \
        --ASSUME_SORT_ORDER coordinate \
        --CREATE_INDEX true \
        --OUTPUT ${base}.md.bam
    
        mv ${base}.md.bai ${base}.md.bam.bai
	"""
}


duplicates_marked_report = duplicates_marked_report.dump(tag:'MarkDuplicates')


process BQSR{

	publishDir path: "$params.outDir/analysis/bqsr", mode: "copy"

	input:
	tuple val(base), file(bam), file(bai) from bam_duplicates_marked
	tuple file(fasta), file(fai), file(dict) from Channel.value([params.fasta, params.fai, params.dict])
	val(intlist) from params.intlist
	tuple file(dbsnp), file(dbsnptbi) from Channel.value([params.dbsnp, params.dbsnptbi])
	tuple file(mills), file(millstbi) from Channel.value([params.mills, params.millstbi])

	output:
	tuple val(base), file("${base}.recal.bam"), file("${base}.recal.bam.bai") into BQSR_bams
	tuple val(base), file("${base}.recal.bam") into bam_recalibrated_qc
	file("${base}.recal.stats.out") into samtoolsStatsReport
	file("${base}.recal.table") into baseRecalibratorReport

	script:
	"""
	gatk --java-options -Xmx8g \
	BaseRecalibrator \
	-I $bam \
	-O ${base}.recal.table \
	-L $intlist \
	--tmp-dir . \
	-R $fasta \
	--known-sites $dbsnp \
	--known-sites $mills 

	gatk --java-options -Xmx8g \
	ApplyBQSR \
	-I $bam \
	-O ${base}.recal.bam \
	-L $intlist \
	-R $fasta \
	--bqsr-recal-file ${base}.recal.table

	samtools index ${base}.recal.bam ${base}.recal.bam.bai
	samtools stats ${base}.recal.bam > ${base}.recal.stats.out
	"""
}

samtoolsStatsReport = samtoolsStatsReport.dump(tag:'SAMToolsStats')

/*
================================================================================
                            GERMLINE VARIANT CALLING
================================================================================
*/


process HaplotypeCaller {

	publishDir path: "$params.outDir/analysis/haplotypecaller", mode: "copy"
	
	input:
	tuple val(base), file(bam), file(bai) from BQSR_bams
	tuple file(fasta), file(fai), file(dict), file(intlist) from Channel.value([params.fasta, params.fai, params.dict, params.intlist])
	tuple file(dbsnp), file(dbsnptbi) from Channel.value([params.dbsnp, params.dbsnptbi])
	
	output:
	tuple val(base), file("${base}.g.vcf") into gvcfHaplotypeCaller
	
	script:
	"""
	gatk --java-options -Xmx8g \
        HaplotypeCaller \
        -R ${fasta} \
        -I ${bam} \
	-L $intlist \
        -D $dbsnp \
        -O ${base}.g.vcf \
        -ERC GVCF
	"""
}


process GenotypeGVCFs {

	publishDir path: "$params.outDir/analysis/genotypeGVCF", mode: "copy"
	
	input:
	tuple val(base), file(gvcf) from gvcfHaplotypeCaller
	tuple file(fasta), file(fai), file(dict), file(intlist) from Channel.value([params.fasta, params.fai, params.dict, params.intlist])
	tuple file(dbsnp), file(dbsnptbi) from Channel.value([params.dbsnp, params.dbsnptbi])
	
	output:
	tuple val(base), file("${base}.vcf") into vcfGenotypeGVCFs
	
	script:
	"""
	gatk --java-options -Xmx8g \
	IndexFeatureFile \
        -I ${gvcf}
	
	gatk --java-options -Xmx8g \
        GenotypeGVCFs \
        -R ${fasta} \
	-L $intlist \
        -D $dbsnp \
        -V ${gvcf} \
        -O ${base}.vcf
	"""
}


/*
================================================================================
                                 SUBSET VARIANTS
================================================================================
*/


process Split_SNPs_Indels{
	
	publishDir path: "$params.outDir/analysis/filter", mode: "copy"
	
	input:
	tuple val(base), file(vcf) from vcfGenotypeGVCFs
	tuple file(fasta), file(fai), file(dict) from Channel.value([params.fasta, params.fai, params.dict])
	
	output:
	tuple val(base), file('*.snps.vcf.gz') into snps_vcf
	tuple val(base), file('*.indels.vcf.gz') into indels_vcf
	
	script:
	"""
	gatk SelectVariants \
	-R $fasta \
    	-V $vcf \
	-O ${base}.snps.vcf.gz \
    	-select-type SNP 
	
	gatk SelectVariants \
	-R $fasta \
    	-V $vcf \
    	-O ${base}.indels.vcf.gz \
    	-select-type INDEL 	
	"""
}


/*
================================================================================
                                 FILTER VARIANTS
================================================================================
*/


process Filter_SNPs{

	publishDir path: "$params.outDir/analysis/filter", mode: "copy"
	
	input:
	tuple val(base), file(vcf) from snps_vcf
	tuple file(fasta), file(fai), file(dict) from Channel.value([params.fasta, params.fai, params.dict])
	
	output:
	tuple val(base), file("${base}_filtsnps.vcf") into snps_filtered
	
	script:
	"""
	gatk --java-options -Xmx8g \
	IndexFeatureFile \
        -I ${vcf}
	
	gatk VariantFiltration \
	-R $fasta \
	-V $vcf \
	-O ${base}_filtsnps.vcf \
	--filter-expression "QD < 2.0" \
	--filter-name "filterQD_lt2.0" \
	--filter-expression "MQ < 25.0" \
	--filter-name "filterMQ_lt25.0" \
	--filter-expression "SOR > 3.0" \
	--filter-name "filterSOR_gt3.0" \
	--filter-expression "MQRankSum < -12.5" \
	--filter-name "filterMQRankSum_lt-12.5" \
	--filter-expression "ReadPosRankSum < -8.0" \
	--filter-name "filterReadPosRankSum_lt-8.0"
	"""
}


process Filter_Indels{

	publishDir path: "$params.outDir/analysis/filter", mode: "copy"
	
	input:
	tuple val(base), file(vcf) from indels_vcf
	tuple file(fasta), file(fai), file(dict) from Channel.value([params.fasta, params.fai, params.dict])
	
	output:
	tuple val(base), file("${base}_filtindels.vcf") into indels_filtered
	
	script:
	"""
	gatk --java-options -Xmx8g \
	IndexFeatureFile \
        -I ${vcf}
	
	gatk VariantFiltration \
	-R $fasta \
	-V $vcf \
	-O ${base}_filtindels.vcf \
	--filter-expression "QD < 2.0" \
	--filter-name "filterQD" \
	--filter-expression "SOR > 10.0" \
	--filter-name "filterSOR_gt10.0" \
	--filter-expression "ReadPosRankSum < -20.0" \
	--filter-name "filterReadPosRankSum"
	"""
}


/*
================================================================================
                                 MERGE VCFs
================================================================================
*/

process Merge_VCFs {

	publishDir path: "$params.outDir/analysis/filtered_vcf", mode: "copy"
	
	input:
	tuple val(base), file(snps) from snps_filtered
	tuple val(base), file(indels) from indels_filtered
	
	output:
	tuple val(base), file("${base}.vcf.gz") into filtered_vcf
	
	script:
	"""
	gatk MergeVcfs \
        -I= $snps \
        -I= $indels \
        -O= ${base}.vcf.gz
	"""
}



(vcfsnpEff, bcfstats, vcfstats) = filtered_vcf.into(3)


/*
================================================================================
                                 ANNOTATION
================================================================================
*/

process snpEff {

	publishDir path: "$params.outDir/analysis/snpEff", mode: "copy"
	
	input:
	tuple val(base), file(vcf) from vcfsnpEff
	val(cache) from params.snpeff_cache
	val(database) from params.snpeff_db
	
	output:
	set file("${base}_snpEff.genes.txt"), file("${base}_snpEff.html"), file("${base}_snpEff.csv") into snpeffReport
        tuple val(base), file("${base}_snpEff.ann.vcf") into snpeffVCF

	script:
	cache = "-dataDir ${cache}"
	"""
	snpEff -Xmx8g \
        ${database} \
        -csvStats ${base}_snpEff.csv \
        -nodownload \
        ${cache} \
        -canon \
        -v \
        ${vcf} \
        > ${base}_snpEff.ann.vcf
	
    	mv snpEff_summary.html ${base}_snpEff.html
	"""
}

