# Uso (a partir da pasta agregador/): Rscript tests/run_tests.R
suppressPackageStartupMessages({
  library(testthat)
  library(tidyverse)
})
test_dir("tests/testthat", reporter = "summary")
