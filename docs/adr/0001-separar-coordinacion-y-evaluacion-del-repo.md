# 0001 - Separar coordinación y evaluación del repo

- Status: accepted
- Date: 2026-10-15

## Context

El orquestador ejecutará skills de Solve en varios repos. Los skills mantienen sus informes actuales y los repos pueden tener reglas de tests y CI distintas, incluso no tener CI. Implementar esas políticas dentro del motor duplicaría decisiones que ya toma el agente caller al usar los skills y condicionaría el contrato de resultados a cada repo.

## Decision

Los agentes autor y reviewer interpretan el dominio y las reglas del repo, eligen y evalúan las verificaciones correspondientes y reportan sus conclusiones. El orquestador administra cola, procesos, sesiones, turnos, límites, etiquetas y persistencia. Valida el esquema JSON y la coherencia técnica de referencias a épica, ejecución, PR y commit. La evaluación semántica permanece en los agentes.

Las repeticiones y correcciones de tests/CI son parte del trabajo interno del agente. El motor no impone ni cuenta esos intentos; conserva los reintentos técnicos de ejecución y el límite de rondas de review como controles de coordinación.

## Alternatives considered

Se consideró que el orquestador identificara los checks obligatorios, consultara sus estados e interpretara cuándo habilitar el PR. Se descartó porque incorpora reglas del repo al motor y duplica responsabilidades del autor y reviewer. Se conserva la comprobación técnica de referencias y commit vigente para coordinar sobre la ejecución correcta.

## Consequences

El motor conserva un contrato de coordinación común y los skills pueden evolucionar sin imponer nuevos formatos a sus informes. Se acepta depender de la interpretación de los agentes para las conclusiones de dominio; la validación de JSON por sí sola no demuestra corrección del código. Deben conservarse evidencia, informes y SHA para que el reviewer y Diego puedan evaluar esas conclusiones. Tests de integración deberán verificar que los resultados del caller permiten dirigir el loop sin introducir políticas específicas de cada repo en el motor.
