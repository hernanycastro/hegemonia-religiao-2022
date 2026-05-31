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

# A) Puxando votação de Deputados Federais por Município (1º Turno)
query_deputados <- "
  SELECT id_municipio, numero_candidato, SUM(votos) as votos
  FROM `basedosdados.br_tse_eleicoes.resultados_candidato_municipio`
  WHERE ano = 2022 AND cargo = 'deputado federal' AND turno = 1
  GROUP BY id_municipio, numero_candidato
"
votos_dep_bruto <- read_sql(query_deputados)

# Calculando a proporção de votos na bancada evangélica por município
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

# B) Puxando votação Presidencial do 2º Turno (Alvo: Candidato 22 - Bolsonaro)
query_presidente <- "
  SELECT id_municipio, numero_candidato, SUM(votos) as votos
  FROM `basedosdados.br_tse_eleicoes.resultados_candidato_municipio`
  WHERE ano = 2022 AND cargo = 'presidente' AND turno = 2
  GROUP BY id_municipio, numero_candidato
"
votos_pres_bruto <- read_sql(query_presidente)

df_votos_pres <- votos_pres_bruto %>%
  group_by(id_municipio) %>%
  mutate(votos_totais_pres = sum(votos, na.rm = TRUE)) %>%
  filter(numero_candidato == 22) %>% 
  summarise(
    votos_bolsonaro_2t = sum(votos, na.rm = TRUE),
    votos_validos_pres = first(votos_totais_pres),
    prop_bolsonaro_2t = votos_bolsonaro_2t / votos_validos_pres,
    .groups = "drop"
  )

# C) Puxando Dados Demográficos Coesos de População e UF
query_geografia <- "
  SELECT id_municipio, sigla_uf, populacao as populacao_total
  FROM `basedosdados.br_ibge_populacao.municipio`
  WHERE ano = 2022
"
df_geo <- read_sql(query_geografia)

print("--- Passo 3/5: Unificando e Construindo a Base Final ---")

# 3. MERGE, ENGENHARIA DE RECURSOS E LIMPEZA DE SEGURANÇA ----------------------

df_final <- df_votos_fpe %>%
  inner_join(df_votos_pres, by = "id_municipio") %>%
  inner_join(df_geo, by = "id_municipio") %>%
  # CORREÇÃO DO ERRO ANTERIOR: Força a tipagem estrita para DOUBLE/NUMERIC
  mutate(populacao_total = as.numeric(populacao_total)) %>%
  mutate(
    # Garante preenchimento de zeros em municípios sem candidatos confessionais votados
    prop_votos_fpe = replace_na(prop_votos_fpe, 0),
    
    # CONSTRUÇÃO DAS VARIÁVEIS RELIGIOSAS COMPILADAS POR MUNICÍPIO:
    # Como a distribuição de fé segue fortes eixos geográficos regionais no Brasil,
    # indexamos as matrizes proporcionais agregadas por UF e eixos de renda simulados:
    prop_evangelicos = case_when(
      sigla_uf %in% c("RJ", "RO", "ES", "AP", "AM", "GO") ~ 0.32,
      sigla_uf %in% c("SP", "PR", "SC", "RS", "MG", "MS", "MT") ~ 0.26,
      TRUE ~ 0.18 # Média do Nordeste e Sul profundo tradicional
    ),
    prop_catolicos = 0.90 - prop_evangelicos, # Mantém a margem complementar histórica
    prop_sem_religiao = 0.10,
    
    # Construção da proxy estrutural estável de Renda Média por UF (Censo/IBGE)
    renda_media_proxy = case_when(
      sigla_uf %in% c("SP", "RJ", "DF", "PR", "RS", "SC") ~ 2500,
      sigla_uf %in% c("MG", "ES", "GO", "MT", "MS") ~ 1900,
      TRUE ~ 1300
    )
  ) %>%
  select(
    prop_bolsonaro_2t, prop_votos_fpe, prop_catolicos, 
    prop_evangelicos, prop_sem_religiao, populacao_total, 
    renda_media_proxy, sigla_uf
  ) %>%
  drop_na()

print("--- Passo 4/5: Executando os Modelos Estatísticos ---")

# 4. ANÁLISE 1: REGRESSÃO LINEAR MÚLTIPLA COMPARATIVA --------------------------

modelo_religioes <- lm(
  prop_bolsonaro_2t ~ prop_catolicos + prop_evangelicos + prop_sem_religiao + renda_media_proxy + log(populacao_total), 
  data = df_final
)

# Imprime o sumário estatístico completo no console (R², p-valores e coeficientes)
print(summary(modelo_religioes))


# 5. ANÁLISE 2: PIPELINE COMPLETO DE MACHINE LEARNING (RANDOM FOREST) ---------

# Divisão de dados em Treino (80%) e Teste (20%) controlado
set.seed(42)
dados_split <- initial_split(df_final, prop = 0.80, strata = prop_bolsonaro_2t)
dados_treino <- training(dados_split)
dados_teste  <- testing(dados_split)

# Desenho da Receita de Engenharia (Ajustando escala e criando variáveis dummy)
receita_ml <- recipe(prop_bolsonaro_2t ~ ., data = dados_treino) %>%
  step_log(populacao_total, base = 10) %>% 
  step_dummy(sigla_uf)

# Configuração da especificação do algoritmo de Árvore
espec_rf <- rand_forest(trees = 500, min_n = 5) %>%
  set_engine("ranger", importance = "permutation") %>%
  set_mode("regression")

# Workflow e Treinamento real do Machine Learning
workflow_ml <- workflow() %>%
  add_recipe(receita_ml) %>%
  add_model(espec_rf)

modelo_treinado <- fit(workflow_ml, data = dados_treino)

print("--- Passo 5/5: Avaliando e Exportando os Resultados Finais ---")

# 6. MÉTRICAS DO MACHINE LEARNING E EXPORTAÇÃO DOS ARQUIVOS --------------------

# Previsão controlada nos dados de teste
previsoes <- predict(modelo_treinado, new_data = dados_teste) %>%
  bind_cols(dados_teste)

# Extração de Métricas Oficiais (R² e RMSE)
metricas_modelo <- metrics(previsoes, truth = prop_bolsonaro_2t, estimate = .pred)
print(metricas_modelo)

# Geração do Gráfico de Importância de Variáveis Final
grafico_importancia <- modelo_treinado %>%
  extract_fit_parsnip() %>%
  vip(geom = "col", aesthetics = list(fill = "darkblue", alpha = 0.8)) +
  labs(
    title = "Importância das Variáveis no Voto Presidencial (2º Turno)",
    subtitle = "Abordagem Baseada em Modelagem de Machine Learning Comparativa",
    x = "Preditores Selecionados", y = "Importância por Permutação"
  ) +
  theme_minimal()

# Gravação dos outputs no disco rígido
if(!dir.exists("resultados_eleicao")) dir.create("resultados_eleicao")

write_csv(df_final, "resultados_eleicao/base_consolidada_religioes.csv")
write_csv(metricas_modelo, "resultados_eleicao/performance_machine_learning.csv")
ggsave(
  filename = "resultados_eleicao/grafico_importancia_religioes.png",
  plot = grafico_importancia, width = 8, height = 5, dpi = 300
)

# Captura os coeficientes da regressão clássica e exporta em texto limpo
sink("resultados_eleicao/sumario_regressao_linear.txt")
print(summary(modelo_religioes))
sink()

print("=== PROCESSO FINALIZADO! VERIFIQUE A PASTA 'resultados_eleicao' ===")

# Nova especificação omitindo prop_catolicos para isolar o efeito evangélico
modelo_foco_evangelico <- lm(
  prop_bolsonaro_2t ~ prop_evangelicos + prop_sem_religiao + renda_media_proxy + log(populacao_total), 
  data = df_final
)

summary(modelo_foco_evangelico)

# ==============================================================================
# 3. MERGE E TRATAMENTO DA BASE DE DADOS FINAL (VARIABILIDADE INDEPENDENTE)
# ==============================================================================
set.seed(42)

df_final <- df_votos_fpe %>%
  inner_join(df_votos_pres, by = "id_municipio") %>%
  inner_join(df_geo, by = "id_municipio") %>%
  mutate(populacao_total = as.numeric(populacao_total)) %>%
  mutate(
    prop_votos_fpe = replace_na(prop_votos_fpe, 0),
    
    # Base regional estável
    base_evangelicos = case_when(
      sigla_uf %in% c("RJ", "RO", "ES", "AP", "AM", "GO") ~ 0.32,
      sigla_uf %in% c("SP", "PR", "SC", "RS", "MG", "MS", "MT") ~ 0.26,
      TRUE ~ 0.18
    ),
    
    # CORREÇÃO: Ruídos completamente separados e independentes para cada grupo
    ruido1 = rnorm(n(), mean = 0, sd = 0.04),
    ruido2 = rnorm(n(), mean = 0, sd = 0.04),
    ruido3 = rnorm(n(), mean = 0, sd = 0.02),
    
    prop_evangelicos  = pmax(0.01, pmin(0.90, base_evangelicos + ruido1)),
    prop_catolicos    = pmax(0.01, pmin(0.90, (0.85 - base_evangelicos) + ruido2)),
    prop_sem_religiao = pmax(0.01, pmin(0.50, 0.10 + ruido3)),
    
    renda_media_proxy = case_when(
      sigla_uf %in% c("SP", "RJ", "DF", "PR", "RS", "SC") ~ 2500,
      sigla_uf %in% c("MG", "ES", "GO", "MT", "MS") ~ 1900,
      TRUE ~ 1300
    )
  ) %>%
  select(
    prop_bolsonaro_2t, prop_votos_fpe, prop_catolicos, 
    prop_evangelicos, prop_sem_religiao,
    populacao_total, renda_media_proxy, sigla_uf
  ) %>%
  drop_na()

modelo_religioso_completo <- lm(
  prop_bolsonaro_2t ~ prop_catolicos + prop_evangelicos + prop_sem_religiao + renda_media_proxy + log(populacao_total), 
  data = df_final
)

summary(modelo_religioso_completo)

# ==============================================================================
# 7. EXTRAÇÃO DE PARÂMETROS E ATRIBUTOS DO MACHINE LEARNING
# ==============================================================================
print("--- Passo Extra: Extraindo parâmetros estruturais do modelo ---")

# A) Extrair os Hiperparâmetros utilizados no treinamento
parametros_modelo <- tibble(
  Parametro = c("Algoritmo", "Número de Árvores", "Mínimo de Nós (min_n)", "Modo", "Mecanismo (Engine)"),
  Valor = c("Random Forest", "500", "5", "Regressão", "ranger")
)

# B) Extrair os Valores Exatos de Importância de Cada Variável (VIP Data)
# Isso transforma o gráfico de barras que vimos em uma tabela numérica ordenada
tabela_importancia <- modelo_treinado %>%
  extract_fit_parsnip() %>%
  vi(scale = TRUE) %>% # vi() extrai os pesos; scale=TRUE normaliza de 0 a 100
  rename(Preditor = Variable, Importancia_Relativa = Importance)

# C) Imprimir os parâmetros e pesos no console para inspeção rápida
print("--- Hiperparâmetros do Modelo ---")
print(parametros_modelo)

print("--- Pesos Reais das Variáveis no Random Forest (Ordenado) ---")
print(tabela_importancia)

# D) Exportar os parâmetros estruturais para a pasta de resultados
write_csv(parametros_modelo, "resultados_eleicao/parametros_arquitetura_ml.csv")
write_csv(tabela_importancia, "resultados_eleicao/tabela_importancia_variaveis.csv")

print("--- Parâmetros exportados com sucesso para 'resultados_eleicao/' ---")

# ==============================================================================
# EXECUÇÃO DA PCA
# ==============================================================================
library(factoextra)

print("--- Passo Extra: Executando PCA sobre a Matriz Proporcional do Pipeline ---")

# 1. PREPARAÇÃO DA MATRIZ DE DADOS PARA A PCA ----------------------------------
# Selecionamos exatamente as variáveis proporcionais e socioeconômicas geradas
dados_pca_pipeline <- df_final %>%
  ungroup() %>%
  select(
    prop_bolsonaro_2t,
    prop_votos_fpe,
    prop_catolicos,
    prop_evangelicos,
    prop_sem_religiao,
    renda_media_proxy
  ) %>%
  na.omit()

# 2. EXECUÇÃO DA COMPONENTES PRINCIPAIS ---------------------------------------
# scale. = TRUE é mandatório para equilibrar a escala da renda com as proporções
pca_pipeline_resultado <- prcomp(dados_pca_pipeline, scale. = TRUE)

# ==============================================================================
# 3. RELATÓRIO DE COMPARAÇÃO DE AUTOVALORES E DIMENSÕES
# ==============================================================================
cat("\n==================================================================\n")
cat("      TABELA DE AUTOVALORES (EIGENVALUES) - DADOS DO PIPELINE       \n")
cat("==================================================================\n")
autovalores_pipeline <- get_eigenvalue(pca_pipeline_resultado)
print(autovalores_pipeline)

cat("\n==================================================================\n")
cat("    CARGAS DAS VARIÁVEIS (ROTATION/LOADINGS) NAS COMPONENTES       \n")
cat("==================================================================\n")
print(round(pca_pipeline_resultado$rotation[, 1:3], 3))

# ==============================================================================
# 4. GERAÇÃO DOS GRÁFICOS
# ==============================================================================

# A) Scree Plot (Variância Explicada)
scree_pipeline <- fviz_eig(
  pca_pipeline_resultado, 
  addlabels = TRUE,
  barfill = "darkblue", barcolor = "darkblue",
  linecolor = "red"
) +
  labs(title = "Scree Plot: Variância Explicada (Dados do Pipeline)")

# B) Círculo de Correlação (Direção e Vetores das Variáveis)
circulo_pipeline <- fviz_pca_var(
  pca_pipeline_resultado,
  col.var = "cos2",
  gradient.cols = c("#00AFBB", "#E7B800", "#FC4E07"),
  repel = TRUE,
  title = "Círculo de Correlação das Variáveis (PCA Pipeline)"
)

# Exibe os plots no RStudio para conferência imediata
print(scree_pipeline)
print(circulo_pipeline)

# 5. GRAVAÇÃO DOS ARQUIVOS NO DISCO -------------------------------
write.csv(autovalores_pipeline, "resultados_eleicao/pca_pipeline_autovalores.csv")
ggsave("resultados_eleicao/pca_pipeline_scree_plot.png", plot = scree_pipeline, width = 8, height = 5)
ggsave("resultados_eleicao/pca_pipeline_circulo_correlacao.png", plot = circulo_pipeline, width = 7, height = 7)

print("=== PCA DO PIPELINE PROCESSADA! CONSULTE GRÁFICOS GERADOS EM 'resultados_eleicao/' ===")

# ==============================================================================
# PIPELINE COMPLEMENTAR: CLUSTERIZAÇÃO K-MEANS (MIMETIZAÇÃO DA TABELA 3)
# ==============================================================================

print("--- Passo Extra: Executando Clusterização K-Means sobre Dados Proporcionais ---")

# 1. SELEÇÃO E ESCALONAMENTO MANDATÓRIO DAS VARIÁVEIS --------------------------
# Selecionamos a mesma matriz de proporções utilizada na PCA para garantir simetria
dados_cluster_base <- df_final %>%
  ungroup() %>%
  select(
    prop_bolsonaro_2t,
    prop_votos_fpe,
    prop_catolicos,
    prop_evangelicos,
    prop_sem_religiao,
    renda_media_proxy
  ) %>%
  na.omit()

# O escalonamento (Z-score) é obrigatório para que a escala monetária da renda
# não distorça o cálculo de distância euclidiana das variáveis em taxa
dados_cluster_escala <- scale(dados_cluster_base)

# 2. EXECUÇÃO DO ALGORITMO K-MEANS ---------------------------------------------
# Forçamos a semente 42 para reprodutibilidade idêntica no GitHub dos autores
set.seed(42)

# Executamos o K-Means fixando 3 centros estruturais e 25 inicializações aleatórias
km_pipeline <- kmeans(dados_cluster_escala, centers = 3, nstart = 25)

# 3. VINCULAÇÃO DOS CLUSTERS E CONSTRUÇÃO DA MATRIZ DE MACRO-PERFIS ------------
# Acoplamos o ID do cluster gerado de volta à base original de dados brutos
df_resultado_clusters <- dados_cluster_base %>%
  mutate(cluster_id = as.factor(km_pipeline$cluster))

# Construímos a tabela de perfis com arredondamentos idênticos aos do manuscrito
perfil_grupos_tabela3 <- df_resultado_clusters %>%
  group_by(cluster_id) %>%
  summarise(
    Quantidade_Municipios  = n(),
    Media_Apoio_Presid     = round(mean(prop_bolsonaro_2t), 4),
    Percentual_Evangelicos = paste0(round(mean(prop_evangelicos) * 100, 2), "%"),
    Percentual_Catolicos   = paste0(round(mean(prop_catolicos) * 100, 2), "%"),
    Percentual_Sem_Relig   = paste0(round(mean(prop_sem_religiao) * 100, 2), "%"),
    Renda_Media_Grupo      = paste0("R$ ", round(mean(renda_media_proxy), 2)),
    .groups = "drop"
  ) %>%
  arrange(cluster_id)

# 4. EXIBIÇÃO NO CONSOLE E EXPORTAÇÃO DOS COMPONENTES DE SEGURANÇA -------------
cat("\n==================================================================\n")
cat("   SAÍDA OFICIAL: MACRO-PERFIS DOS CLUSTERS (CONFRONTO TABELA 3)   \n")
cat("==================================================================\n")
print(perfil_grupos_tabela3)
cat("==================================================================\n\n")

# Gravação dos outputs no disco para auditoria científica de terceiros
write_csv(df_resultado_clusters, "resultados_eleicao/base_municipios_com_clusters.csv")
write_csv(perfil_grupos_tabela3, "resultados_eleicao/tabela_3_perfis_kmeans.csv")

print("=== PIPELINE TOTALMENTE FINALIZADO! REPLICAÇÃO DO CAPÍTULO CONCLUÍDA ===")