# Etapa 5: agregador (votos válidos, razão com João, pesos, efeito de instituto,
# regressão local) com as pesquisas publicadas até o corte.
# Saídas em data/processed/: agregador.rds, agregador_diario.csv, house_effects.csv

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/modelo.R", encoding = "UTF-8")
source("programs/functions/pipeline.R", encoding = "UTF-8")

candidatos <- ler_csv_manual("candidatos.csv")
pesquisas <- ler_proc("pesquisas_long.csv")

ag <- rodar_agregador(pesquisas, CFG$corte, candidatos)
saveRDS(ag, file.path(DIR$processados, "agregador.rds"))

escrever_proc(ag$validos |> left_join(ag$curvas, by = c("data", "candidato")),
              "agregador_diario.csv")
he <- as_tibble(ag$h, rownames = "instituto") |>
  pivot_longer(-instituto, names_to = "candidato", values_to = "h_log") |>
  mutate(h_relativo = exp(h_log) - 1) |>
  left_join(count(distinct(ag$base, protocolo, instituto), instituto, name = "n_pesquisas"),
            by = "instituto")
escrever_proc(he, "house_effects.csv")

fim <- ag$validos |> filter(data == ag$ultima) |> arrange(desc(validos))
message(sprintf("%d pesquisas, última em %s; iterações do efeito de instituto: %s",
                n_distinct(ag$base$protocolo), ag$ultima, attr(ag$h, "iteracoes")))
print(fim |> mutate(validos = round(100 * validos, 1)), n = Inf)
