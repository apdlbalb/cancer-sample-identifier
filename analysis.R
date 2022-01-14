# LIBRARIES -----------------------------------------------------------------
#install.packages("rentrez")
library(rentrez)
#install.packages("tidyverse")
library(tidyverse)
#install.packages("randomForest")
library(randomForest)
#if (!requireNamespace("BiocManager", quietly = TRUE))
#  install.packages("BiocManager")
#BiocManager::install("GEOquery")
library(GEOquery)
#BiocManager::install("Biostrings")
library(Biostrings)

NUMBER_OF_GROUP_SAMPLES_RANDOM_FOREST = 20

GEODATASET = "GSE10780"
SAMPLE_TYPE1_IDENTIFIER = "Normal"
SAMPLE_TYPE1_NAME = "Normal"
SAMPLE_TYPE2_IDENTIFIER = "carcinoma"
SAMPLE_TYPE2_NAME = "Carcinoma"

# Probes corresponding to marker genes
# Platform: GPL570 [HG-U133_Plus_2] Affymetrix Human Genome U133 Plus 2.0 Array
MARKER_PROBES = t(data.frame(c("ESR1", "205225_at"),
                             c("ERBB2", "210930_s_at"),
                             c("ESR2", "211117_x_at"),
                             c("BRCA1", "204531_s_at"),
                             c("BRCA2", "208368_s_at"),
                             c("PGR", "208305_at"),
                             c("TP53", "201746_at")))

NUM_MARKERS = 7

# FUNCTIONS ---------------------------------------------------------------------

# getMarkerExpression obtains the gene expression values of molecular markers defined in "dfMarkerProbes"
# for the samples listed in "dfSampleSet", which contains a list of "numSamples" samples.
# (dataframeof "accession" "title" Marker_1...Marker_n) <- Int 
#                                                          (dataframeof "accession" "title")
#                                                          (dataframeof GeneSymbol ProbeID)
# Requires: Samples must exist in the GEO database
#           R package GEOquery

getMarkerExpression <- function(numSamples, dfSampleSet, dfMarkerProbes) {
  NA_index = vector()
  
  for (i in 1:(2 * numSamples)) {
    temp_expression_data <- Table(getGEO(dfSampleSet[i,]$accession))
    
    for (j in 1:nrow(dfMarkerProbes)) {
      temp_marker_abundance <- temp_expression_data[temp_expression_data$ID_REF == dfMarkerProbes[j,2],]$VALUE
      if (length(temp_marker_abundance) == 0) {
        NA_index <- c(NA_index, i)
      } else {
        dfSampleSet[i,j+2] <- temp_marker_abundance
      }
    }
  }
  
  if (length(NA_index) > 0) {
    dfSampleSet <- dfSampleSet[-unique(NA_index),]
  }
  colnames(dfSampleSet) <- c("accession", "title", dfMarkerProbes[,1])
  return(dfSampleSet)
}

# GET DATA -------------------------------------------------------------------------

# Pull list of samples in GEO dataset.
GSE_search <- entrez_search("gds", term = paste(GEODATASET, " AND gsm[Entry Type]"), retmax = 1000)

# Pull related information about samples.
GSE_search_summaries <- entrez_summary("gds", id = GSE_search$ids)

# Subset sample summaries to just the accession numbers and sample types 
GSE_samples <- as.data.frame(t(extract_from_esummary(GSE_search_summaries, elements = c("accession", "title"))))

# Rename elements in 'title' column so that they are easier to handle
# in downstream analysis.
GSE_samples[grep(pattern = SAMPLE_TYPE1_IDENTIFIER, GSE_samples$title),2] <- SAMPLE_TYPE1_NAME
GSE_samples[grep(pattern = SAMPLE_TYPE2_IDENTIFIER, GSE_samples$title),2] <- SAMPLE_TYPE2_NAME

# Sample the list of samples for the validation set.
dfValidation <- GSE_samples %>%
                group_by(title) %>%
                sample_n(NUMBER_OF_GROUP_SAMPLES_RANDOM_FOREST)

# Prepare columns for marker gene expression data.
dfValidation[,3:(2+NUM_MARKERS)] <- NA

# Populate marker gene expression columns with data from the sample set.
dfValidation <- getMarkerExpression(NUMBER_OF_GROUP_SAMPLES_RANDOM_FOREST, dfValidation, MARKER_PROBES)

# Sample the list of samples for the training set.
dfTraining <- GSE_samples %>%
              filter(!accession %in% dfValidation$accession) %>%
              group_by(title) %>%
              sample_n(NUMBER_OF_GROUP_SAMPLES_RANDOM_FOREST)

# Prepare columns for marker gene expression data.
dfTraining[,3:(2+NUM_MARKERS)] <- NA

# Populate marker gene expression columns with data from the sample set.
dfTraining <- getMarkerExpression(NUMBER_OF_GROUP_SAMPLES_RANDOM_FOREST, dfTraining, MARKER_PROBES)

# Re-organize tidy data for boxplot.
bp_markers <- rep(MARKER_PROBES[,1], each = length(dfValidation$accession))
bp_tissue_type <- rep(c(rep(SAMPLE_TYPE1_NAME, 
                              length(dfValidation[dfValidation$title == SAMPLE_TYPE1_NAME,]$accession)), 
                          rep(SAMPLE_TYPE2_NAME, 
                              length(dfValidation[dfValidation$title == SAMPLE_TYPE2_NAME,]$accession))),
                        7)
bp_expression <- c(dfValidation[[3]],
                   dfValidation[[4]],
                   dfValidation[[5]],
                   dfValidation[[6]],
                   dfValidation[[7]],
                   dfValidation[[8]],
                   dfValidation[[9]])
                   

# Boxplot!
bp_data <- data.frame(bp_markers, bp_tissue_type, bp_expression)
bp <- boxplot(bp_expression ~ bp_tissue_type * bp_markers, 
        bp_data, 
        boxwex = 0.4,
        col = c("pink", "chartreuse"),
        xaxt = "n",
        ylab = "Gene expression (au)",
        xlab = "Molecular Marker")

# Simplify x-axis labels to only markers
my_names <- sapply(strsplit(bp$names , '\\.') , function(x) x[[2]] )
my_names <- my_names[seq(1 , length(my_names) , 2)]
axis(1, 
     at = seq(1.5 , 14 , 2), 
     labels = my_names , 
     tick=FALSE , cex=0.3)      

# Add lines that separate boxes by markers
for(i in seq(0.5 , 20 , 2)){ 
  abline(v=i,lty=1, col="lightgrey")
}

# Add a legend
legend("topleft", 
       legend = c(SAMPLE_TYPE2_NAME, SAMPLE_TYPE1_NAME),
       col = c("pink", "chartreuse"),
       pch = 15, bty = "n", pt.cex = 3, cex = 1.2,  horiz = F, inset = c(0.1, 0.1))

# RANDOM FOREST CLASSIFIER --------------------------------------------------------

# Create random forest model based on training set.
sample_classifier <- randomForest::randomForest(x = dfTraining[, 3:9], 
                                                y = as.factor(unlist(dfTraining$title)), 
                                                ntree = 100, 
                                                importance = TRUE)
sample_classifier


# Test classifier on validation set.
predictValidation <- predict(sample_classifier, dfValidation[, 3:9])
cmatrix <- table(observed = unlist(dfValidation$title), predicted = predictValidation)

# Create four fold plot for the confusion matrix.
fourfoldplot(cmatrix, 
             color = c("chartreuse", "#ffe6e6"), 
             conf.level = 0,
             std = c("margins"),
             margin = 1, space = 0.2, main = NULL,
             mfrow = NULL, mfcol = NULL)


