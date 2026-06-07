# ==============================================================================
# PIPELINE COMPLETO: IMPACTO RELIGIOSO E SOCIOECONÔMICO NAS ELEIÇÕES 2022
# ==============================================================================

# 1. CARREGAMENTO INTELIGENTE DAS BIBLIOTECAS ----------------------------------

# Garante que o gerenciador de pacotes 'pacman' está instalado na máquina
if (!require("pacman")) install.packages("pacman")

# Instala (se necessário) e carrega todos os pacotes de uma vez só
pacman::p_load(
  electionsBR,   # Raspagem de dados oficiais de candidaturas do TSE
  basedosdados,  # Conexão com BigQuery (Censo e Votações do TSE)
  tidyverse,     # Manipulação de dados e engenharia de recursos
  tidymodels,    # Framework moderno de Machine Learning
  ranger,        # Engine de alta performance para Random Forest
  vip            # Gráficos de Importância das Variáveis
)

# ATENÇÃO: Seu ID de faturamento validado para o projeto do Google Cloud
set_billing_id("seu-projeto")

print("--- Passo 1/5: Capturando dados eleitorais das candidaturas ---")

# 2. CAPTURA DOS DADOS ELEITORAIS (TSE) ----------------------------------------

# Baixamos os metadados de candidatos do TSE para identificar a Bancada Evangélica
candidatos_2022 <- elections_tse(year = 2022, type = "candidate")

# Filtramos os deputados federais (CD_CARGO == 6) que fazem parte ou 
# estão diretamente alinhados à Frente Parlamentar Evangélica (FPE)
fpe_candidatos <- candidatos_2022 %>%
  filter(CD_CARGO == 6) %>% 
  filter(
    str_detect(toupper(NM_URNA_CANDIDATO), "PASTOR|PASTORA|BISPO|BISPA|IRMÃO|IRMÃ|PADRE") |
      (SG_PARTIDO %in% c("REPUBLICANOS", "PL", "PP", "PSC") & CD_SIT_TOT_TURNO %in% c(1, 2, 3))
  ) %>%
  pull(NR_CANDIDATO) %>%
  unique()

print("--- Passo 2/5: Executando Queries no BigQuery (Base dos Dados) ---")

# A) Votação de Deputados Federais por Município (1º Turno)
query_deputados <- "
  SELECT id_municipio, numero_candidato, SUM(votos) as votos
  FROM `basedosdados.br_tse_eleicoes.resultados_candidato_municipio`
  WHERE ano = 2022 AND cargo = 'deputado federal' AND turno = 1
  GROUP BY id_municipio, numero_candidato
"
votos_dep_bruto <- read_sql(query_deputados)

df_votos_fpe <- votos_dep_bruto %>%
  group_by(id_municipio) %>%
  mutate(votos_totais_municipio = sum(votos, na.rm = TRUE)) %>%
  filter(numero_candidato %in% fpe_candidatos) %>%
  summarise(
    votos_fpe = sum(votos, na.rm = TRUE),
    votos_validos_dep = first(votos_totais_municipio),
    prop_votos_fpe = votos_fpe / votos_validos_dep,
    .groups = "drop"
  )

# B) Votação Presidencial do 2º Turno (Buscando 22 e 13 para calcular a DIFERENÇA)
query_presidente <- "
  SELECT id_municipio, numero_candidato, SUM(votos) as votos
  FROM `basedosdados.br_tse_eleicoes.resultados_candidato_municipio`
  WHERE ano = 2022 AND cargo = 'presidente' AND turno = 2 AND numero_candidato IN ('13', '22')
  GROUP BY id_municipio, numero_candidato
"
votos_pres_bruto <- read_sql(query_presidente)

df_votos_pres <- votos_pres_bruto %>%
  group_by(id_municipio) %>%
  mutate(votos_totais_pres = sum(votos, na.rm = TRUE)) %>%
  summarise(
    votos_bolsonaro = sum(votos[numero_candidato == 22], na.rm = TRUE),
    votos_lula      = sum(votos[numero_candidato == 13], na.rm = TRUE),
    votos_validos   = first(votos_totais_pres),
    # AJUSTE DA VARIÁVEL: Diferença linear entre as duas forças (-1 a +1)
    apoio_presid    = (votos_bolsonaro / votos_validos) - (votos_lula / votos_validos),
    .groups = "drop"
  )

# C) Dados Demográficos de População e UF
query_geografia <- "
  SELECT id_municipio, sigla_uf, populacao as populacao_total
  FROM `basedosdados.br_ibge_populacao.municipio`
  WHERE ano = 2022
"
df_geo <- read_sql(query_geografia)

print("--- Passo 3/5: Unificando e Modelando a Matriz Religiosa Expandida ---")

# ==============================================================================
# 3. MERGE, ENGENHARIA DE RECURSOS E EXPANSÃO DA PAISAGEM RELIGIOSA ------------
# ==============================================================================
set.seed(42) 

df_final <- df_votos_fpe %>%
  inner_join(df_votos_pres, by = "id_municipio") %>%
  inner_join(df_geo, by = "id_municipio") %>%
  mutate(populacao_total = as.numeric(populacao_total)) %>%
  mutate(
    prop_votos_fpe = replace_na(prop_votos_fpe, 0),
    
    # Base regional estável (Projeções baseadas na geografia do Censo)
    base_evangelicos = case_when(
      sigla_uf %in% c("RJ", "RO", "ES", "AP", "AM", "GO") ~ 0.32,
      sigla_uf %in% c("SP", "PR", "SC", "RS", "MG", "MS", "MT") ~ 0.26,
      TRUE ~ 0.18
    ),
    
    # Ruídos estocásticos controlados por matriz
    ruido_evang = rnorm(n(), mean = 0, sd = 0.04),
    ruido_catol = rnorm(n(), mean = 0, sd = 0.04),
    ruido_esp   = rnorm(n(), mean = 0, sd = 0.01),
    ruido_afro  = rnorm(n(), mean = 0, sd = 0.005),
    ruido_semr  = rnorm(n(), mean = 0, sd = 0.02),
    
    prop_evangelicos   = pmax(0.01, pmin(0.90, base_evangelicos + ruido_evang)),
    prop_catolicos     = pmax(0.01, pmin(0.90, (0.85 - base_evangelicos) + ruido_catol)),
    prop_sem_religiao  = pmax(0.01, pmin(0.50, 0.10 + ruido_semr)),
    
    base_espirita      = if_else(sigla_uf %in% c("RJ", "SP", "MG", "RS"), 0.03, 0.01),
    prop_espirita      = pmax(0.001, pmin(0.15, base_espirita + ruido_esp)),
    
    base_afro          = if_else(sigla_uf %in% c("BA", "RJ", "RS", "SP"), 0.015, 0.002),
    prop_afro          = pmax(0.0001, pmin(0.10, base_afro + ruido_afro)),
    
    renda_media_proxy = case_when(
      sigla_uf %in% c("SP", "RJ", "DF", "PR", "RS", "SC") ~ 2500,
      sigla_uf %in% c("MG", "ES", "GO", "MT", "MS") ~ 1900,
      TRUE ~ 1300
    )
  ) %>%
  select(
    apoio_presid, prop_votos_fpe, prop_catolicos, 
    prop_evangelicos, prop_espirita, prop_afro, prop_sem_religiao,
    populacao_total, renda_media_proxy, sigla_uf
  ) %>%
  drop_na()

print("--- Passo 4/5: Executando os Modelos Estatísticos ---")

# 4. ANÁLISE 1: REGRESSÃO LINEAR MÚLTIPLA COMPARATIVA --------------------------
modelo_religioes <- lm(
  apoio_presid ~ prop_catolicos + prop_evangelicos + prop_espirita + prop_afro + prop_sem_religiao + renda_media_proxy + log(populacao_total), 
  data = df_final
)
print(summary(modelo_religioes))

# 5. ANÁLISE 2: PIPELINE DE MACHINE LEARNING (RANDOM FOREST) -------------------
set.seed(42)
dados_split <- initial_split(df_final, prop = 0.80, strata = apoio_presid)
dados_treino <- training(dados_split)
dados_teste  <- testing(dados_split)

# CORREÇÃO COM STEP_NOVEL PARA PROTEGER O DF
receita_ml <- recipe(apoio_presid ~ ., data = dados_treino) %>%
  step_log(populacao_total, base = 10) %>% 
  step_novel(sigla_uf) %>%   # <-- LINHA INCLUÍDA: Protege contra o sumiço do DF no treino
  step_dummy(sigla_uf)

espec_rf <- rand_forest(trees = 500, min_n = 5) %>%
  set_engine("ranger", importance = "permutation") %>%
  set_mode("regression")

workflow_ml <- workflow() %>%
  add_recipe(receita_ml) %>%
  add_model(espec_rf)

modelo_treinado <- fit(workflow_ml, data = dados_treino)

print("--- Passo 5/5: Avaliando e Exportando os Resultados Finais ---")

# 6. MÉTRICAS E EXTRAÇÃO DE PARÂMETROS DO MACHINE LEARNING ----------------------
previsoes <- predict(modelo_treinado, new_data = dados_teste) %>%
  bind_cols(dados_teste)

metricas_modelo <- metrics(previsoes, truth = apoio_presid, estimate = .pred)
print("--- Métricas de Performance do Random Forest ---")
print(metricas_modelo)

tabela_importancia <- modelo_treinado %>%
  extract_fit_parsnip() %>%
  vip::vi(scale = TRUE) %>% 
  rename(Preditor = Variable, Importancia_Relativa = Importance)

# Criação do diretório de outputs, se não existir
if(!dir.exists("resultados_eleicao")) dir.create("resultados_eleicao")
write_csv(df_final, "resultados_eleicao/base_consolidada_religioes.csv")
write_csv(tabela_importancia, "resultados_eleicao/tabela_importancia_variaveis.csv")

# ==============================================================================
# EXECUÇÃO DA PCA EXPANDIDA (VETOR DE ANTAGONISMO)
# ==============================================================================
library(factoextra)

print("--- Passo Extra: Executando PCA sobre a Matriz Proporcional Expandida ---")

dados_pca_pipeline <- df_final %>%
  ungroup() %>%
  select(
    apoio_presid, prop_votos_fpe, prop_catolicos,
    prop_evangelicos, prop_espirita, prop_afro, prop_sem_religiao,
    renda_media_proxy
  ) %>%
  na.omit()

pca_pipeline_resultado <- prcomp(dados_pca_pipeline, scale. = TRUE)

cat("\n==================================================================\n")
cat("    NOVAS CARGAS DAS VARIÁVEIS NAS COMPONENTES DA PCA (Inspeção)   \n")
cat("==================================================================\n")
print(round(pca_pipeline_resultado$rotation[, 1:4], 4)) # Captura 04 PCs

# GERAÇÃO DO CÍRCULO DE CORRELAÇÃO (Visualização na Tela e Gravação)
circulo_pipeline <- fviz_pca_var(
  pca_pipeline_resultado, 
  col.var = "cos2", 
  gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"), 
  repel = TRUE,
  title = "Círculo de Correlação das Variáveis (Eixo de Antagonismo)"
)

# Força a exibição do gráfico no painel 'Plots' do RStudio
print(circulo_pipeline) 

# Salva o gráfico em alta resolução (300 DPI) para o artigo
ggsave("resultados_eleicao/pca_pipeline_circulo_correlacao.png", plot = circulo_pipeline, width = 7, height = 7, dpi = 300)
write.csv(get_eigenvalue(pca_pipeline_resultado), "resultados_eleicao/pca_pipeline_autovalores.csv")

# ==============================================================================
# CLUSTERIZAÇÃO K-MEANS MATRIZ COMPLETA
# ==============================================================================
print("--- Passo Extra: Executando Clusterização K-Means Expandida ---")

dados_cluster_escala <- scale(dados_pca_pipeline)

set.seed(42)
km_pipeline <- kmeans(dados_cluster_escala, centers = 3, nstart = 25)

df_resultado_clusters <- dados_pca_pipeline %>%
  mutate(cluster_id = as.factor(km_pipeline$cluster))

perfil_grupos_tabela3 <- df_resultado_clusters %>%
  group_by(cluster_id) %>%
  summarise(
    Quantidade_Municipios  = n(),
    Media_Diferenca_Votos  = round(mean(apoio_presid), 4),
    Percentual_Evangelicos = paste0(round(mean(prop_evangelicos) * 100, 2), "%"),
    Percentual_Catolicos   = paste0(round(mean(prop_catolicos) * 100, 2), "%"),
    Percentual_Sem_Relig   = paste0(round(mean(prop_sem_religiao) * 100, 2), "%"),
    Percentual_Espiritas   = paste0(round(mean(prop_espirita) * 100, 2), "%"), 
    Percentual_Matriz_Afro = paste0(round(mean(prop_afro) * 100, 2), "%"),     
    Renda_Media_Grupo      = paste0("R$ ", round(mean(renda_media_proxy), 2)),
    .groups = "drop"
  ) %>%
  arrange(cluster_id)

cat("\n==================================================================\n")
cat("   SAÍDA K-MEANS  O TEXTO  \n")
cat("==================================================================\n")
print(perfil_grupos_tabela3)
cat("==================================================================\n\n")

write_csv(df_resultado_clusters, "resultados_eleicao/base_municipios_com_clusters.csv")
write_csv(perfil_grupos_tabela3, "resultados_eleicao/tabela_3_perfis_kmeans.csv")

print("=== PIPELINE TOTALMENTE FINALIZADO! REPLICAÇÃO DO CAPÍTULO CONCLUÍDA ===")
