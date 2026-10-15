# Etapa 6: projeção para o dia da eleição, Tabela 1 e sensibilidade.

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")
source("programs/functions/modelo.R", encoding = "UTF-8")
source("programs/functions/pipeline.R", encoding = "UTF-8")

candidatos <- ler_csv_manual("candidatos.csv")
pesquisas <- ler_proc("pesquisas_long.csv")
dir.create(DIR$saida, showWarnings = FALSE)

# variações de um parâmetro por vez; as marcadas com refaz = TRUE reajustam o
# agregador. Para sigmas e banda, o valor multiplica o do config; kappa,
# penalidade e eixo de data recebem o valor diretamente.
variacoes <- tribble(
  ~parametro,          ~valor,       ~refaz,
  "sigma_sistematico", "0.75",       FALSE,   # extremos do IC 90% (c04)
  "sigma_sistematico", "1.35",       FALSE,
  "sigma_deriva_dia",  "0",          FALSE,
  "sigma_deriva_dia",  "2",          FALSE,
  "kappa",             "0",          TRUE,
  "kappa",             "Inf",        TRUE,
  "banda_dias",        "0.5",        TRUE,
  "banda_dias",        "2",          TRUE,
  "usar_penalidade",   "0",          TRUE,
  "data_pesquisa",     "meio",       TRUE,
  "data_pesquisa",     "divulgacao", TRUE
)

ag <- readRDS(file.path(DIR$processados, "agregador.rds"))

principal <- projetar(ag)
# fração de indecisos: mediana das pesquisas que entraram no agregador
u_indecisos <- ler_proc("indecisos.csv") |>
  filter(protocolo %in% ag$base$protocolo) |>
  pull(frac_indecisos) |>
  median()
message(sprintf("Fração de indecisos (mediana das pesquisas): %.1f%%", 100 * u_indecisos))
indecisos <- projetar(ag, ajuste_validos = ajuste_indecisos(u_indecisos, CFG$indecisos_beneficiados))

tabela <- principal |>
  left_join(candidatos |> select(candidato, nome_urna, partido), by = "candidato") |>
  mutate(across(c(projecao, faixa_inf, faixa_sup, mediana_sim, prob_eleito), \(x) round(100 * x, 1)))
escrever_proc(tabela, "projecao.csv")
write_csv(tabela, file.path(DIR$saida, "tabela_1.csv"), na = "")

probs <- bind_rows(
  principal |> transmute(candidato, cenario = "Projeção principal", prob_eleito),
  indecisos |> transmute(candidato, cenario = "Indecisos divididos entre Veneziano e Nabor", prob_eleito)
)
escrever_proc(probs, "probabilidades.csv")

aplicar_variacao <- function(par, parametro, valor) {
  par[[parametro]] <- switch(parametro,
    usar_penalidade = as.numeric(valor) == 1,
    data_pesquisa = valor,
    kappa = as.numeric(valor),
    as.numeric(valor) * par[[parametro]]
  )
  par
}

sens <- pmap_dfr(variacoes, function(parametro, valor, refaz) {
  if (parametro == "data_pesquisa" && valor == CFG$data_pesquisa) return(NULL)
  par <- aplicar_variacao(CFG, parametro, valor)
  par$n_sims <- 50000
  a <- if (refaz) rodar_agregador(pesquisas, CFG$corte, candidatos, par) else ag
  usado <- as.character(par[[parametro]])
  projetar(a, par) |>
    filter(candidato %in% c("JOAO_AZEVEDO", "VENEZIANO", "NABOR")) |>
    transmute(parametro, valor = usado, candidato, projecao, prob_eleito)
})
escrever_proc(sens, "sensibilidade.csv")
write_csv(sens |> mutate(across(c(projecao, prob_eleito), \(x) round(100 * x, 1))),
          file.path(DIR$saida, "sensibilidade.csv"), na = "")

message(sprintf("Última pesquisa %s, %d dias até a eleição, sigma total %.3f",
                ag$ultima, principal$dias[1], principal$sigma[1]))
print(tabela |> select(candidato, projecao, faixa_inf, faixa_sup, prob_eleito), n = Inf)
message("Sensibilidade (indecisos):")
print(indecisos |> filter(candidato %in% c("JOAO_AZEVEDO", "VENEZIANO", "NABOR")) |>
        mutate(prob_eleito = round(100 * prob_eleito, 1)) |> select(candidato, prob_eleito))
message("Sensibilidade (um parâmetro por vez), faixa de P(eleito):")
print(sens |> group_by(candidato) |>
        summarise(min = round(100 * min(prob_eleito), 1), max = round(100 * max(prob_eleito), 1)))
