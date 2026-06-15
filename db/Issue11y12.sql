-- ============================================================
-- ISSUE #11: Gestión de Comisiones de Análisis e Informes
-- ============================================================

-- Tabla principal de comisiones
CREATE TABLE comisiones (
    id_comision    SERIAL PRIMARY KEY,
    nombre         VARCHAR(255) NOT NULL,
    -- Objeto de la comisión según el acta de creación
    objeto         TEXT NOT NULL,
    fecha_creacion DATE DEFAULT CURRENT_DATE,
    estado         VARCHAR(50) DEFAULT 'Activa'
);

-- Tabla de relación: asambleístas asignados a una comisión
-- Un asambleísta puede estar en varias comisiones
CREATE TABLE comision_integrantes (
    id_comision        INT NOT NULL REFERENCES comisiones(id_comision) ON DELETE CASCADE,
    cedula_asambleista VARCHAR(50) NOT NULL REFERENCES asambleistas(cedula) ON DELETE CASCADE,
    fecha_asignacion   DATE DEFAULT CURRENT_DATE,
    PRIMARY KEY (id_comision, cedula_asambleista)
);

-- Tabla de sesiones de la asamblea
CREATE TABLE sesiones (
    id_sesion    SERIAL PRIMARY KEY,
    titulo       VARCHAR(255) NOT NULL,
    fecha_sesion DATE NOT NULL,
    estado       VARCHAR(50) DEFAULT 'Convocada'   -- Convocada, Realizada, Cancelada
);

-- Tabla de informes/puntos de agenda dentro de una sesión
CREATE TABLE informes_sesion (
    id_informe    SERIAL PRIMARY KEY,
    id_sesion     INT NOT NULL REFERENCES sesiones(id_sesion) ON DELETE CASCADE,
    -- Comisión que presenta el informe
    id_comision   INT REFERENCES comisiones(id_comision),
    titulo_punto  VARCHAR(255) NOT NULL,
    descripcion   TEXT
);

-- Tabla de relación: un informe puede tocar varios artículos del reglamento
CREATE TABLE informe_articulos (
    id_informe    INT NOT NULL REFERENCES informes_sesion(id_informe) ON DELETE CASCADE,
    id_reglamento INT NOT NULL REFERENCES reglamentos(id_reglamento) ON DELETE CASCADE,
    PRIMARY KEY (id_informe, id_reglamento)
);


-- ============================================================
-- ISSUE #12: Control de Asistencias y Cálculo de Participación
-- ============================================================

-- Tabla de asistencia: quién asistió a qué sesión
-- Se llena desde los nombramientos vigentes al momento de la sesión
CREATE TABLE asistencia_sesiones (
    id_asistencia      SERIAL PRIMARY KEY,
    id_sesion          INT NOT NULL REFERENCES sesiones(id_sesion) ON DELETE CASCADE,
    cedula_asambleista VARCHAR(50) NOT NULL REFERENCES asambleistas(cedula),
    estado_asistencia  VARCHAR(20) NOT NULL DEFAULT 'Ausente'
        CHECK (estado_asistencia IN ('Presente', 'Ausente')),
    -- Timestamp del servidor, no del cliente, para evitar manipulación
    registrado_en      TIMESTAMPTZ DEFAULT NOW()
);

-- Restricción: un asambleísta solo puede tener un registro de asistencia por sesión
CREATE UNIQUE INDEX idx_asistencia_unica
    ON asistencia_sesiones (id_sesion, cedula_asambleista);


-- Función para calcular el porcentaje de asistencia de un asambleísta en un rango de fechas
-- Ejemplo de uso: SELECT calcularPorcentajeAsistencia('11111111', '2026-01-01', '2026-12-31');
CREATE OR REPLACE FUNCTION calcularPorcentajeAsistencia(
    p_cedula  VARCHAR,
    p_inicio  DATE,
    p_fin     DATE
)
RETURNS NUMERIC AS $$
DECLARE
    total_sesiones    INT;
    sesiones_presente INT;
BEGIN
    -- Contar sesiones convocadas en el periodo
    SELECT COUNT(*) INTO total_sesiones
    FROM sesiones
    WHERE fecha_sesion BETWEEN p_inicio AND p_fin
      AND estado = 'Realizada';

    IF total_sesiones = 0 THEN
        RETURN 0;
    END IF;

    -- Contar sesiones donde el asambleísta estuvo presente
    SELECT COUNT(*) INTO sesiones_presente
    FROM asistencia_sesiones a
    JOIN sesiones s ON a.id_sesion = s.id_sesion
    WHERE a.cedula_asambleista = p_cedula
      AND a.estado_asistencia = 'Presente'
      AND s.fecha_sesion BETWEEN p_inicio AND p_fin
      AND s.estado = 'Realizada';

    RETURN ROUND((sesiones_presente::NUMERIC / total_sesiones) * 100, 2);
END;
$$ LANGUAGE plpgsql;


-- Tabla de votaciones nominales (voto público, mayoría simple)
CREATE TABLE votaciones (
    id_votacion   SERIAL PRIMARY KEY,
    id_sesion     INT NOT NULL REFERENCES sesiones(id_sesion) ON DELETE CASCADE,
    -- El informe/punto de agenda que se está votando (opcional)
    id_informe    INT REFERENCES informes_sesion(id_informe),
    descripcion   TEXT NOT NULL,
    -- Se calcula automáticamente al registrar votos individuales
    votos_favor   INT DEFAULT 0,
    votos_contra  INT DEFAULT 0,
    votos_abstenc INT DEFAULT 0,
    -- Resultado calculado automáticamente por el trigger de abajo
    resultado     VARCHAR(20) DEFAULT 'Pendiente'
        CHECK (resultado IN ('Pendiente', 'Aprobado', 'Rechazado')),
    fecha_votacion TIMESTAMPTZ DEFAULT NOW()
);

-- Tabla de votos individuales (voto nominal = público y trazable)
CREATE TABLE votos_nominales (
    id_voto            SERIAL PRIMARY KEY,
    id_votacion        INT NOT NULL REFERENCES votaciones(id_votacion) ON DELETE CASCADE,
    cedula_asambleista VARCHAR(50) NOT NULL REFERENCES asambleistas(cedula),
    voto               VARCHAR(20) NOT NULL
        CHECK (voto IN ('A Favor', 'En Contra', 'Abstención'))
);

-- Un asambleísta solo puede votar una vez por votación
CREATE UNIQUE INDEX idx_voto_unico
    ON votos_nominales (id_votacion, cedula_asambleista);

-- Trigger para recalcular totales y aplicar validación de mayoría simple (50%+1)
-- al insertar un voto individual
CREATE OR REPLACE FUNCTION actualizar_resultado_votacion()
RETURNS TRIGGER AS $$
DECLARE
    total_votos    INT;
    v_favor        INT;
    v_contra       INT;
    v_abstencion   INT;
BEGIN
    SELECT
        COUNT(*) FILTER (WHERE voto = 'A Favor'),
        COUNT(*) FILTER (WHERE voto = 'En Contra'),
        COUNT(*) FILTER (WHERE voto = 'Abstención'),
        COUNT(*)
    INTO v_favor, v_contra, v_abstencion, total_votos
    FROM votos_nominales
    WHERE id_votacion = NEW.id_votacion;

    -- Mayoría simple: más votos a favor que en contra (50%+1 del total votante)
    UPDATE votaciones
    SET votos_favor  = v_favor,
        votos_contra = v_contra,
        votos_abstenc = v_abstencion,
        -- Solo se determina si cumple mayoría simple
        resultado = CASE
            WHEN v_favor > v_contra THEN 'Aprobado'
            ELSE 'Rechazado'
        END
    WHERE id_votacion = NEW.id_votacion;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_actualizar_votacion
AFTER INSERT ON votos_nominales
FOR EACH ROW
EXECUTE FUNCTION actualizar_resultado_votacion();