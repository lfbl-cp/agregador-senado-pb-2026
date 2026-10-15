# Calibração, etapa 3: consolida as duas coletas independentes (A e B) das
# pesquisas de 2014, 2018 e 2022 e grava a base no formato de pesquisas_long.
#
# Entradas
#   data/manual/calibration/coleta_{A,B}_<ano>.csv   coletas independentes
#   data/manual/calibration/decisoes_historicas.csv  resolução de divergências e
#                                                    abrangência (opcional)
#   data/processed/calibration/fichas_historicas.csv, resultados_tse.csv
# Saídas (data/processed/calibration/)
#   comparacao_historicas.csv  concordância A x B por pesquisa e cargo
#   pesquisas_historicas.csv   base para c04/c05 (só pesquisas conferidas)

source("programs/00_config.R", encoding = "UTF-8")
source("programs/functions/util.R", encoding = "UTF-8")

dir_man <- file.path(DIR$manuais, "calibration")
fichas <- ler_proc("calibration/fichas_historicas.csv")
res <- ler_proc("calibration/resultados_tse.csv", col_types = cols(numero = "c"))
NAO_CAND <- c("BRANCO_NULO", "NAO_SABE", "OUTROS", "NENHUM")
TOL <- 0.6   # diferença máxima (p.p.) para considerar dois registros iguais

ler_coleta <- function(f) {
  read_csv(f, col_types = cols(.default = "c"), locale = locale(encoding = "UTF-8")) |>
    mutate(coletor = str_extract(basename(f), "(?<=coleta_)[AB]"),
           ano = as.integer(ano), turno = as.integer(turno), pct = as.numeric(pct),
           n = as.integer(n), across(starts_with("data_"), as.Date))
}
coletas <- list.files(dir_man, "^coleta_[AB]_\\d{4}\\.csv$", full.names = TRUE) |>
  map_dfr(ler_coleta) |>
  mutate(cargo = str_to_lower(cargo), formato = coalesce(formato, ""))

# --- candidato da fonte -> número do TSE ------------------------------------------
# Casa pelo sobrenome/apelido: algum token (>= 4 letras) do nome da fonte aparece
# no nome de urna do TSE. Ambiguidades ou nomes sem par são listados.
tokens <- function(x) str_split(sem_acento(x), "[^A-Z]+") |> map(\(t) t[nchar(t) >= 4 & !t %in% c("FILHO", "JUNIOR", "NETO", "PROFESSOR", "PROFESSORA", "PASTOR", "MAJOR", "DOUTOR")])
tse_nomes <- res |> filter(ano %in% CAL$eleicoes$ano) |> distinct(ano, turno, cargo, numero, nome_urna)
nomes <- coletas |>
  filter(!candidato %in% NAO_CAND, !is.na(candidato), candidato != "") |>
  distinct(ano, turno, cargo, candidato)
mapa <- nomes |>
  mutate(numero = pmap_chr(list(ano, turno, cargo, candidato), function(a, tu, ca, nm) {
    alvo <- tse_nomes |> filter(ano == a, turno == tu, cargo == ca)
    tk <- tokens(nm)[[1]]
    hit <- alvo$numero[map_lgl(tokens(alvo$nome_urna), \(t) any(tk %in% t))]
    if (length(hit) == 1) hit else NA_character_
  }))
manual <- file.path(dir_man, "mapa_candidatos.csv")
if (file.exists(manual)) {
  m <- read_csv(manual, col_types = cols(.default = "c")) |> mutate(ano = as.integer(ano), turno = as.integer(turno))
  mapa <- mapa |> rows_update(m, by = c("ano", "turno", "cargo", "candidato"), unmatched = "ignore")
}
sem_par <- mapa |> filter(is.na(numero))
if (nrow(sem_par)) {
  message("Nomes sem candidato do TSE (fora da disputa ou a resolver em mapa_candidatos.csv):")
  print(sem_par, n = Inf)
}

coletas <- coletas |>
  left_join(mapa, by = c("ano", "turno", "cargo", "candidato")) |>
  mutate(id = case_when(candidato %in% NAO_CAND ~ candidato,
                        !is.na(numero) ~ paste0("N", numero),
                        TRUE ~ paste0("X:", sem_acento(candidato))))

# --- formato por pesquisa e cargo -------------------------------------------------
# Log-razão é a mesma em votos totais ou válidos (1 vaga) e em soma, média ou
# citações (2 vagas); primeiro e segundo voto isolados não entram. Em 2018, o
# "validos" do Senado tem bases diferentes entre fontes e só entra como último recurso.
ORDEM <- c("total", "soma", "media", "citacoes", "validos")
escolher <- function(df) {
  df |>
    filter(status == "encontrada", formato %in% ORDEM, !is.na(pct)) |>
    group_by(coletor, ano, turno, cargo, protocolo) |>
    mutate(ncand = n_distinct(id[!id %in% NAO_CAND])) |>
    group_by(cenario, formato, .add = TRUE) |>
    mutate(ncand_conj = n_distinct(id[!id %in% NAO_CAND])) |>
    ungroup(cenario, formato) |>
    # vence o conjunto com mais candidatos; no empate, a ordem de ORDEM e o cenário c1
    filter(ncand_conj == max(ncand_conj)) |>
    filter(match(formato, ORDEM) == min(match(formato, ORDEM))) |>
    filter(cenario == sort(unique(cenario))[1]) |>
    ungroup() |>
    select(-ncand, -ncand_conj)
}
esc <- escolher(coletas)

# --- comparação A x B -------------------------------------------------------------
lado <- function(x) {
  # só candidatos da disputa (com número no TSE): nomes fora dela não entram nas razões
  esc |> filter(coletor == x, str_starts(id, "N")) |>
    select(ano, turno, cargo, protocolo, id, formato, pct)
}
comp <- full_join(lado("A"), lado("B"), by = c("ano", "turno", "cargo", "protocolo", "id"),
                  suffix = c("_A", "_B")) |>
  group_by(ano, turno, cargo, protocolo) |>
  summarise(
    candidatos = n(),
    formato_A = first(na.omit(formato_A)), formato_B = first(na.omit(formato_B)),
    # candidato com até 1% registrado só de um lado ("não pontuou" vs omitido) não conta
    so_A = sum(!is.na(pct_A) & is.na(pct_B) & pct_A > 1),
    so_B = sum(is.na(pct_A) & !is.na(pct_B) & pct_B > 1),
    max_dif = suppressWarnings(max(abs(pct_A - pct_B), na.rm = TRUE)),
    .groups = "drop"
  ) |>
  mutate(
    max_dif = if_else(is.finite(max_dif), max_dif, NA_real_),
    situacao = case_when(
      is.na(formato_A) ~ "so_B",
      is.na(formato_B) ~ "so_A",
      formato_A != formato_B ~ "formatos_diferentes",
      max_dif <= TOL & so_A == 0 & so_B == 0 ~ "conferido_duplo",
      TRUE ~ "divergente"
    )
  )

# decisões manuais: protocolo, cargo, turno, decisao (usar_A | usar_B | excluir), nota
arq_dec <- file.path(dir_man, "decisoes_historicas.csv")
dec <- if (file.exists(arq_dec)) {
  read_csv(arq_dec, col_types = cols(.default = "c")) |> mutate(turno = as.integer(turno))
} else {
  tibble(protocolo = character(), cargo = character(), turno = integer(), decisao = character(), nota = character())
}
comp <- comp |>
  left_join(dec, by = c("protocolo", "cargo", "turno")) |>
  mutate(fonte_final = case_when(
    decisao == "excluir" ~ NA_character_,
    decisao == "usar_A" ~ "A",
    decisao == "usar_B" ~ "B",
    situacao == "conferido_duplo" ~ "A",
    TRUE ~ NA_character_
  ))
escrever_proc(comp, "calibration/comparacao_historicas.csv")
message("Concordância A x B:")
print(count(comp, ano, situacao))

# --- base final ----------------------------------------------------------------------
disputas <- CAL$eleicoes |>
  cross_join(tibble(cargo = c("governador", "senador"))) |>
  filter(!(cargo == "senador" & turno == 2)) |>
  mutate(disputa = sprintf("%s_%d_t%d", substr(cargo, 1, 3), ano, turno))

base <- esc |>
  inner_join(comp |> filter(!is.na(fonte_final)) |> select(ano, turno, cargo, protocolo, fonte_final),
             by = c("ano", "turno", "cargo", "protocolo", coletor = "fonte_final")) |>
  filter(!id %in% NAO_CAND) |>
  left_join(fichas |> distinct(protocolo, n_tse = n, inicio_tse = data_inicio, fim_tse = data_fim),
            by = "protocolo") |>
  inner_join(disputas, by = c("ano", "turno", "cargo")) |>
  mutate(
    n = coalesce(n, n_tse),
    data_inicio = coalesce(data_inicio, inicio_tse),
    data_fim = coalesce(data_fim, fim_tse),
    instituto = sem_acento(instituto) |>
      str_remove_all("\\b(INSTITUTO|PESQUISAS?|LTDA|DE|E|CONSULTORIA)\\b") |>
      str_squish() |> word(1)
  ) |>
  # mesma janela das fichas: 1º turno, fim de campo até janela_dias antes; 2º
  # turno, depois do 1º
  group_by(ano) |>
  mutate(primeiro = min(data_eleicao)) |>
  ungroup() |>
  filter(!is.na(n), !is.na(data_publicacao), data_publicacao < data_eleicao,
         if_else(turno == 1, data_fim >= data_eleicao - CAL$janela_dias, data_fim > primeiro)) |>
  select(-primeiro)

# referência = maior média nas pesquisas; com curva = média >= 3% dos votos dos
# candidatos testados (decidido só com as pesquisas, sem olhar o resultado).
# Candidatos com votos anulados (zero válido, ex.: Ricardo Coutinho, Senado 2022)
# não têm razão no resultado e ficam fora; a razão entre os demais não muda.
validos_tse <- res |> filter(votos > 0) |> transmute(ano, turno, cargo, id = paste0("N", numero))
medias <- base |>
  group_by(disputa, protocolo) |>
  mutate(share = pct / sum(pct)) |>
  semi_join(validos_tse, by = c("ano", "turno", "cargo", "id")) |>
  group_by(disputa, id) |>
  summarise(media = mean(share), presenca = n(), .groups = "drop_last") |>
  mutate(referencia = id[which.max(media)], modelado = media >= 0.03 & presenca >= 3) |>
  ungroup()

base <- base |>
  left_join(medias |> select(disputa, id, modelado), by = c("disputa", "id")) |>
  left_join(medias |> distinct(disputa, referencia), by = "disputa") |>
  mutate(modelado = coalesce(modelado, FALSE)) |>
  transmute(disputa, ano, turno, cargo, data_eleicao, protocolo, instituto, data_publicacao,
            data_inicio, data_fim, n, cenario, formato, candidato = id,
            numero, pct, fonte_url, referencia, modelado)
escrever_proc(base, "calibration/pesquisas_historicas.csv")

message("Base histórica:")
print(base |> group_by(disputa) |>
        summarise(pesquisas = n_distinct(protocolo), institutos = n_distinct(instituto),
                  candidatos_curva = n_distinct(candidato[modelado]), referencia = first(referencia)))
