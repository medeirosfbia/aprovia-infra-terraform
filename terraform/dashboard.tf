# Dashboard do ambiente (Azure Workbook) com consultas KQL sobre o Log Analytics
locals {
  workbook_queries = [
    {
      title         = "Requisições da API e falhas (5 min)"
      visualization = "timechart"
      query         = "AppRequests | where AppRoleName !startswith 'func-' | summarize Total = count(), Falhas = countif(Success == false) by bin(TimeGenerated, 5m) | render timechart"
    },
    {
      title         = "Tempo de resposta da API, p50 e p95 (ms)"
      visualization = "timechart"
      query         = "AppRequests | where AppRoleName !startswith 'func-' | summarize p50 = percentile(DurationMs, 50), p95 = percentile(DurationMs, 95) by bin(TimeGenerated, 15m) | render timechart"
    },
    {
      title         = "Disponibilidade das duas APIs (%)"
      visualization = "timechart"
      query         = "AppAvailabilityResults | summarize Disponibilidade = 100.0 * countif(Success == true) / count() by bin(TimeGenerated, 15m), Name | render timechart"
    },
    {
      title         = "Execuções da Function App por função"
      visualization = "barchart"
      query         = "AppRequests | where AppRoleName startswith 'func-' | summarize Sucesso = countif(Success == true), Falha = countif(Success == false) by OperationName | render barchart"
    },
    {
      title         = "Exceções por componente (1 h)"
      visualization = "timechart"
      query         = "AppExceptions | summarize Excecoes = count() by bin(TimeGenerated, 1h), AppRoleName | render timechart"
    },
    {
      title         = "VM: CPU e memória usadas (%)"
      visualization = "timechart"
      query         = "Perf | where (ObjectName == 'Processor' and CounterName == '% Processor Time' and InstanceName == '_Total') or (ObjectName == 'Memory' and CounterName == '% Used Memory') | summarize Valor = avg(CounterValue) by bin(TimeGenerated, 5m), CounterName | render timechart"
    },
    {
      title         = "VM: disco usado (%)"
      visualization = "table"
      query         = "Perf | where ObjectName == 'Logical Disk' and CounterName == '% Used Space' and InstanceName != '_Total' | summarize arg_max(TimeGenerated, CounterValue) by InstanceName | project Disco = InstanceName, UsoPercentual = round(CounterValue, 1)"
    },
    {
      title         = "Filas: mensagens publicadas x consumidas (1 h)"
      visualization = "timechart"
      query         = "StorageQueueLogs | where OperationName in ('PutMessage', 'DeleteMessage') | summarize Operacoes = count() by bin(TimeGenerated, 1h), OperationName | render timechart"
    },
    {
      title         = "Blob: uploads, downloads e exclusões por container"
      visualization = "barchart"
      query         = "StorageBlobLogs | where OperationName in ('PutBlob', 'GetBlob', 'DeleteBlob') | extend Container = tostring(split(ObjectKey, '/')[2]) | summarize Operacoes = count() by Container, OperationName | render barchart"
    },
    {
      title         = "API Java (Container Apps): réplicas e reinícios"
      visualization = "timechart"
      query         = "ContainerAppSystemLogs_CL | where ContainerAppName_s == 'ca-aprovia-java' | summarize Eventos = count() by bin(TimeGenerated, 1h), Reason_s | render timechart"
    },
    {
      title         = "API Java: erros no log"
      visualization = "timechart"
      query         = "ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'ca-aprovia-java' and Log_s has_any ('ERROR', 'Exception') | summarize Erros = count() by bin(TimeGenerated, 1h) | render timechart"
    },
    {
      title         = "PostgreSQL: CPU, armazenamento e conexões"
      visualization = "timechart"
      query         = "AzureMetrics | where ResourceProvider == 'MICROSOFT.DBFORPOSTGRESQL' and MetricName in ('cpu_percent', 'storage_percent', 'active_connections') | summarize Valor = avg(Average) by bin(TimeGenerated, 15m), MetricName | render timechart"
    },
  ]
}

resource "random_uuid" "workbook" {}

resource "azurerm_application_insights_workbook" "ambiente" {
  name                = random_uuid.workbook.result
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  display_name        = "AprovIA - Monitoramento do ambiente"
  source_id           = lower(azurerm_log_analytics_workspace.main.id)
  category            = "workbook"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = concat(
      [{
        type = 1
        name = "titulo"
        content = {
          json = "## AprovIA - Monitoramento do ambiente\nAPI Python (VM), API Java (Container Apps), Function App, PostgreSQL, Storage Account (Blob e Queue). Dados do Log Analytics `log-aprovia`."
        }
      }],
      [for i, q in local.workbook_queries : {
        type = 3
        name = "consulta-${i}"
        content = {
          version       = "KqlItem/1.0"
          query         = q.query
          size          = 0
          title         = q.title
          timeContext   = { durationMs = 86400000 }
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = q.visualization
        }
        customWidth = "50"
      }]
    )
    fallbackResourceIds = [lower(azurerm_log_analytics_workspace.main.id)]
    "$schema"           = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
  })

  tags = var.tags
}
