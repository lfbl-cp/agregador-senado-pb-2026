# Calibração com eleições anteriores

Gerado por `programs/calibration/c06_relatorio.R`. Os parâmetros foram escolhidos pelas regras
registradas em `programs/00_config.R` antes da comparação com o resultado de 2026.

## Base histórica

Pesquisas estaduais de Governo e Senado na PB (2014, 2018, 2022), coletadas por dois coletores
independentes e, quando só um achou a fonte, conferidas por releitura cega.

| Disputa | Pesquisas | Institutos | Com curva |
| --- | --- | --- | --- |
| gov_2014_t1 | 11 | 4 | 3 |
| gov_2014_t2 |  4 | 2 | 2 |
| gov_2018_t1 | 14 | 7 | 3 |
| gov_2022_t1 | 13 | 7 | 4 |
| gov_2022_t2 |  5 | 2 | 2 |
| sen_2014_t1 | 11 | 4 | 3 |
| sen_2018_t1 | 10 | 6 | 5 |
| sen_2022_t1 | 14 | 7 | 4 |

| Situação | Pesquisa × cargo |
| --- | --- |
| conferido_duplo | 72 |
| divergente |  3 |
| so_A |  7 |
| so_B |  9 |

## Validação cruzada (banda, κ, eixo de data)

Erro quadrático padronizado médio ao prever cada pesquisa só com as publicadas antes dela
(origem móvel), somando Senado 2026 e as disputas acima. Eixo: meio do campo.

| Banda (dias) | κ = 0 | κ = 0.5 | κ = 1 | κ = 2 | κ = 4 | κ = Inf |
| --- | --- | --- | --- | --- | --- | --- |
|  12 | 25,89 | 18,02 | 15,35 | 13,34 | 12,39 | 13,87 |
|  16 | 15,00 | 12,18 | 11,47 | 11,14 | 11,28 | 13,54 |
|  24 | 13,70 | 11,37 | 10,84 | 10,69 | 10,99 | 13,49 |
|  32 | 13,56 | 11,28 | 10,75 | 10,61 | 10,93 | 13,56 |
|  48 | 13,32 | 11,14 | 10,59 | 10,43 | 10,74 | 13,41 |
|  64 | 13,29 | 11,16 | 10,62 | 10,45 | 10,75 | 13,41 |
|  96 | 13,40 | 11,31 | 10,76 | 10,58 | 10,87 | 13,50 |
| 128 | 13,55 | 11,45 | 10,90 | 10,69 | 10,96 | 13,54 |

Eixo: data de divulgação.

| Banda (dias) | κ = 0 | κ = 0.5 | κ = 1 | κ = 2 | κ = 4 | κ = Inf |
| --- | --- | --- | --- | --- | --- | --- |
|  12 | 15,45 | 12,81 | 12,04 | 11,56 | 11,55 | 13,89 |
|  16 | 14,35 | 11,99 | 11,36 | 11,07 | 11,24 | 13,58 |
|  24 | 13,89 | 11,63 | 11,06 | 10,85 | 11,11 | 13,55 |
|  32 | 13,69 | 11,49 | 10,94 | 10,76 | 11,05 | 13,63 |
|  48 | 13,35 | 11,26 | 10,72 | 10,54 | 10,83 | 13,47 |
|  64 | 13,27 | 11,23 | 10,70 | 10,52 | 10,81 | 13,43 |
|  96 | 13,33 | 11,33 | 10,80 | 10,61 | 10,89 | 13,48 |
| 128 | 13,46 | 11,45 | 10,91 | 10,71 | 10,97 | 13,51 |

Menor erro: banda 48 dias, κ = 2, eixo meio (z² = 10,43).

## Erro do agregador contra o resultado

Erro na véspera, por disputa e candidato (log-razão contra o líder das pesquisas):

| Disputa | Líder (referência) | Candidato | Agregador (log) | Resultado (log) | Erro |
| --- | --- | --- | --- | --- | --- |
| gov_2014_t1 | Cassio Cunha Lima | Vital | -2,44 | -2,21 | 0,23 |
| gov_2014_t1 | Cassio Cunha Lima | Ricardo Coutinho | -0,08 | -0,03 | 0,05 |
| sen_2014_t1 | Jose Maranhão | Lucélio Cartaxo | -0,65 | -0,22 | 0,44 |
| sen_2014_t1 | Jose Maranhão | Wilson Santiago | -0,72 | -0,25 | 0,48 |
| gov_2014_t2 | Ricardo Coutinho | Cassio Cunha Lima | -0,09 | -0,10 | -0,01 |
| gov_2018_t1 | João | Zé Maranhão | -0,44 | -1,20 | -0,77 |
| gov_2018_t1 | João | Lucélio Cartaxo | -0,67 | -0,91 | -0,24 |
| sen_2018_t1 | Cássio Cunha Lima | Daniella Ribeiro | -0,25 | 0,32 | 0,58 |
| sen_2018_t1 | Cássio Cunha Lima | Luiz Couto | -0,24 | 0,28 | 0,51 |
| sen_2018_t1 | Cássio Cunha Lima | Roberto Paulino | -0,97 | -0,83 | 0,14 |
| sen_2018_t1 | Cássio Cunha Lima | Veneziano | 0,02 | 0,34 | 0,32 |
| gov_2022_t1 | João | Veneziano | -0,50 | -0,84 | -0,34 |
| gov_2022_t1 | João | Nilvan Ferreira | -0,73 | -0,75 | -0,02 |
| gov_2022_t1 | João | Pedro Cunha Lima | -0,75 | -0,51 | 0,24 |
| sen_2022_t1 | Efraim Filho | Bruno Roberto | -0,99 | -0,98 | 0,01 |
| sen_2022_t1 | Efraim Filho | Sergio Queiroz | -1,17 | -0,97 | 0,20 |
| sen_2022_t1 | Efraim Filho | Pollyanna | -0,24 | -0,30 | -0,06 |
| gov_2022_t2 | João | Pedro Cunha Lima | -0,16 | -0,10 | 0,06 |

Máxima verossimilhança por horizonte (dias entre o corte e a eleição). s: erro por candidato;
t: choque próprio do líder; b: viés comum do líder (erro-padrão entre parênteses).

| Horizonte | Modelo | s | IC 90% de s | t | b | AIC | Disputas | Dias (média) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  0 | s | 0,223 | 0,168–0,296 |  |  | 8,8 | 8 | 2,4 |
|  0 | s+t | 0,209 | 0,144–0,304 | 0,251 |  | 10,6 | 8 | 2,4 |
|  0 | s+b | 0,219 | 0,165–0,291 |  | 0,076 (0,096) | 10,2 | 8 | 2,4 |
|  0 | s+t+b | 0,210 | 0,144–0,306 | 0,238 | 0,074 (0,100) | 12,1 | 8 | 2,4 |
|  7 | s | 0,279 | 0,208–0,374 |  |  | 15,9 | 7 | 12,4 |
|  7 | s+t | 0,237 | 0,161–0,349 | 0,359 |  | 17,0 | 7 | 12,4 |
|  7 | s+b | 0,269 | 0,200–0,361 |  | 0,136 (0,124) | 16,8 | 7 | 12,4 |
|  7 | s+t+b | 0,237 | 0,161–0,350 | 0,332 | 0,131 (0,141) | 18,2 | 7 | 12,4 |
| 14 | s | 0,345 | 0,254–0,467 |  |  | 21,7 | 6 | 19,5 |
| 14 | s+t | 0,289 | 0,194–0,431 | 0,457 |  | 22,8 | 6 | 19,5 |
| 14 | s+b | 0,337 | 0,248–0,457 |  | 0,131 (0,164) | 23,1 | 6 | 19,5 |
| 14 | s+t+b | 0,290 | 0,194–0,433 | 0,436 | 0,123 (0,194) | 24,4 | 6 | 19,5 |
| 21 | s | 0,402 | 0,297–0,544 |  |  | 26,6 | 6 | 34,8 |
| 21 | s+t | 0,309 | 0,207–0,462 | 0,577 |  | 26,8 | 6 | 34,8 |
| 21 | s+b | 0,386 | 0,284–0,524 |  | 0,206 (0,188) | 27,5 | 6 | 34,8 |
| 21 | s+t+b | 0,310 | 0,207–0,464 | 0,538 | 0,196 (0,235) | 28,1 | 6 | 34,8 |
| 28 | s | 0,425 | 0,314–0,575 |  |  | 28,4 | 6 | 36,8 |
| 28 | s+t | 0,314 | 0,208–0,472 | 0,626 |  | 28,1 | 6 | 36,8 |
| 28 | s+b | 0,401 | 0,295–0,545 |  | 0,258 (0,195) | 28,7 | 6 | 36,8 |
| 28 | s+t+b | 0,314 | 0,208–0,474 | 0,570 | 0,247 (0,248) | 29,2 | 6 | 36,8 |

Deriva (inclinação de s² contra os dias): σ_d = 0,061 por raiz de dia; σ_s = 0,202.
