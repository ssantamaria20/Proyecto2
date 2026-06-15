-- Creacion de la tabla recursiva para Reglamentos(Issue 10)
CREATE TABLE reglamentos (
    id_reglamento SERIAL PRIMARY KEY,
    nombre VARCHAR(255) NOT NULL,
    contenido TEXT,
    -- Apunta al ID del elemento que lo contiene.
    id_padre INT REFERENCES reglamentos(id_reglamento) ON DELETE CASCADE
);

-- Creacion de la tabla para Asamblea (Issue 9)
CREATE TABLE asambleistas (
    cedula VARCHAR(50) PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    primer_apellido VARCHAR(150) NOT NULL,
    segundo_apellido VARCHAR(150),
    correo VARCHAR(255) UNIQUE NOT NULL
);

--Ajuste tabla issue 9
-- Añadir la columna sector y estado a la tabla de nombramientos
ALTER TABLE nombramientos 
ADD COLUMN sector VARCHAR(150),
ADD COLUMN estado VARCHAR(50) DEFAULT 'Vigente';

--Reajuste de tabla issue 10, para cumplir con criterios de aceptacion

--Eliminar la tabla
DROP TABLE IF EXISTS reglamentos CASCADE;

-- Crear la tabla recursiva con soporte de versionamiento historico
CREATE TABLE reglamentos (
    id_reglamento SERIAL PRIMARY KEY,
    id_coherente_articulo VARCHAR(50) NOT NULL, 
    nombre VARCHAR(255) NOT NULL,              -
    contenido TEXT,
    id_padre INT REFERENCES reglamentos(id_reglamento) ON DELETE CASCADE, 
    
    -- Control de Versionamiento Historico
    num_resolucion VARCHAR(100) DEFAULT 'AIR-RES-000',
    fecha_inicio_vigencia DATE DEFAULT CURRENT_DATE,
    fecha_fin_vigencia DATE,
    estado_vigencia VARCHAR(50) DEFAULT 'Activo', 
    version INT DEFAULT 1
);

-- RESTRICCION DE UNICIDAD PARCIAL 
CREATE UNIQUE INDEX idx_articulo_vigente_unico 
ON reglamentos (id_coherente_articulo) 
WHERE (estado_vigencia = 'Activo' AND fecha_fin_vigencia IS NULL);


-- TRIGGER PARA EL VERSIONAMIENTO AUTOMÁTICO
CREATE OR REPLACE FUNCTION procesar_reforma_reglamento()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado_vigencia = 'Activo' THEN
        UPDATE reglamentos
        SET estado_vigencia = 'Histórico',
            fecha_fin_vigencia = CURRENT_DATE
        WHERE id_coherente_articulo = NEW.id_coherente_articulo 
          AND estado_vigencia = 'Activo'
          AND id_reglamento <> NEW.id_reglamento;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el disparador de la tabla
CREATE TRIGGER trigger_reforma_reglamento
BEFORE INSERT ON reglamentos
FOR EACH ROW
EXECUTE FUNCTION procesar_reforma_reglamento();

-- FIN DE AJUSTE ISSUE 10

-- AJUSTES ISSUE 15

CREATE TABLE certificaciones (
    id_certificacion SERIAL PRIMARY KEY,
    num_folio VARCHAR(50) UNIQUE NOT NULL,     
    cedula_asambleista VARCHAR(50) NOT NULL,
    puesto_asignado VARCHAR(100) NOT NULL,
    estado VARCHAR(20) DEFAULT 'Activo',        
    motivo_anulacion TEXT,                    
    sustituye_a_folio VARCHAR(50),             
    fecha_emision DATE DEFAULT CURRENT_DATE
);

INSERT INTO certificaciones (num_folio, cedula_asambleista, puesto_asignado, estado)
VALUES 
('DAIR-101-2026', '11111111', 'Presidente', 'Activo'),
('DAIR-102-2026', '22222222', 'Secretario', 'Activo');

-- Issue 13

-- Secuencias y tablas de auditorias

-- Secuencia para el consecutivo del folio 
CREATE SEQUENCE IF NOT EXISTS folio_certificacion_seq START 1;

-- Tabla log_certificacione

CREATE TABLE IF NOT EXISTS log_certificaciones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consecutivo VARCHAR(50) NOT NULL,
    asambleista_id UUID, -- Registra el ID del asambleísta consultado
    usuario_id UUID,     -- Registra quién lo hizo 
    hash_documento TEXT,
    accion VARCHAR(20) NOT NULL, -- 'EMISION' o 'BORRADO'
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT now() -- Hora exacta del servidor
);

-- Tabla de auditoria para accesos
CREATE TABLE IF NOT EXISTS seguridad_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID DEFAULT auth.uid(),
    asambleista_id UUID,
    tipo_acceso VARCHAR(50) NOT NULL, -- 'CONSULTA_ASAMBLEISTA'
    genero_certificacion BOOLEAN DEFAULT false,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT now()
);


-- Ajustes a Bd para el issue


ALTER TABLE certificaciones ADD COLUMN IF NOT EXISTS folio VARCHAR(50) UNIQUE;
ALTER TABLE certificaciones ADD COLUMN IF NOT EXISTS codigo_verificacion UUID DEFAULT gen_random_uuid();
ALTER TABLE certificaciones ADD COLUMN IF NOT EXISTS asambleista_id UUID;
ALTER TABLE certificaciones ADD COLUMN IF NOT EXISTS usuario_emisor_id UUID DEFAULT auth.uid();

-- Funciones y triggers

-- Funcion genera folio fecha
CREATE OR REPLACE FUNCTION generar_folio_certificacion()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.folio IS NULL THEN
        NEW.folio := 'DAIR-' || LPAD(nextval('folio_certificacion_seq')::TEXT, 3, '0') || '-' || to_char(now(), 'YYYY');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger Adignar folio
DROP TRIGGER IF EXISTS trg_generar_folio ON certificaciones;
CREATE TRIGGER trg_generar_folio
BEFORE INSERT ON certificaciones
FOR EACH ROW EXECUTE FUNCTION generar_folio_certificacion();


-- Funcion bitacora de auditoria
CREATE OR REPLACE FUNCTION auditar_certificacion()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- Registro de emision
        INSERT INTO log_certificaciones (consecutivo, asambleista_id, usuario_id, accion)
        VALUES (NEW.folio, NEW.asambleista_id, NEW.usuario_emisor_id, 'EMISION');
        RETURN NEW;
        
    ELSIF (TG_OP = 'DELETE') THEN
        -- Registro de borrado
        INSERT INTO log_certificaciones (consecutivo, asambleista_id, usuario_id, accion)
        VALUES (OLD.folio, OLD.asambleista_id, coalesce(auth.uid(), OLD.usuario_emisor_id), 'BORRADO');
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger de de guardar en bitacora
DROP TRIGGER IF EXISTS trg_auditoria_certificaciones ON certificaciones;
CREATE TRIGGER trg_auditoria_certificaciones
AFTER INSERT OR DELETE ON certificaciones
FOR EACH ROW EXECUTE FUNCTION auditar_certificacion();

-- Politicas de seguridad
ALTER TABLE log_certificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE seguridad_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Permitir lectura de logs" ON log_certificaciones;
DROP POLICY IF EXISTS "Permitir inserción de logs" ON log_certificaciones;
DROP POLICY IF EXISTS "Permitir lectura seguridad" ON seguridad_logs;
DROP POLICY IF EXISTS "Permitir inserción seguridad" ON seguridad_logs;

CREATE POLICY "Permitir lectura de logs" ON log_certificaciones FOR SELECT USING (true);
CREATE POLICY "Permitir inserción de logs" ON log_certificaciones FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir lectura seguridad" ON seguridad_logs FOR SELECT USING (true);
CREATE POLICY "Permitir inserción seguridad" ON seguridad_logs FOR INSERT WITH CHECK (true);

-- Issue 17

-- Tablas de auditorias
CREATE TABLE IF NOT EXISTS solicitudes_certificacion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario_id UUID DEFAULT auth.uid(), -- Quien la solicito
    cedula_consultada VARCHAR(20) NOT NULL,
    folio_asignado VARCHAR(50) UNIQUE NOT NULL,
    creado_en TIMESTAMP WITH TIME ZONE DEFAULT now()  Fecha/Hora del servidor
);

-- Ajustes BD 
ALTER TABLE solicitudes_certificacion ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Permitir inserción de solicitudes" ON solicitudes_certificacion FOR INSERT WITH CHECK (true);
CREATE POLICY "Permitir lectura de solicitudes" ON solicitudes_certificacion FOR SELECT USING (true);

-- Indice para tiempo menor de respuesta
CREATE INDEX IF NOT EXISTS idx_solicitudes_cedula ON solicitudes_certificacion(cedula_consultada);
CREATE INDEX IF NOT EXISTS idx_asambleistas_cedula ON asambleistas(cedula);

-- Vsita de datos
CREATE OR REPLACE VIEW vw_asambleista_hoja_vida AS
SELECT 
    a.id AS asambleista_id,
    a.cedula,
    a.nombre_completo,

    COALESCE(
        string_agg(DISTINCT n.periodo || ' (' || n.cargo || ')', ', '), 
        'Sin períodos registrados'
    ) AS periodos_gestion,
    
    -- Calculo del procentaje de asistencia exacta a sesiones
    CASE 
        WHEN COUNT(asist.id) = 0 THEN 0
        ELSE ROUND((COUNT(CASE WHEN asist.asistio = true THEN 1 END)::NUMERIC / COUNT(asist.id)::NUMERIC) * 100, 2)
    END AS porcentaje_asistencia,
    
    -- Lista compacta de propuestas 
    COALESCE(
        string_agg(DISTINCT '• ' || p.titulo || ' [' || p.estado || ']', CHR(10)), 
        '• No registra propuestas ni reformas.'
    ) AS lista_propuestas
    
FROM asambleistas a
LEFT JOIN nombramientos n ON a.id = n.asambleista_id
LEFT JOIN asistencias asist ON a.id = asist.asambleista_id
LEFT JOIN propuestas_reformas p ON a.id = p.asambleista_id
GROUP BY a.id, a.cedula, a.nombre_completo;

-- Motor del certificado
CREATE OR REPLACE FUNCTION generar_certificado_asambleista(p_cedula TEXT)
RETURNS TABLE (
    folio VARCHAR,
    fecha_emision TEXT,
    contenido_certificado TEXT
) AS $$
DECLARE
    v_folio VARCHAR;
    v_asambleista RECORD;
BEGIN
    -- Buscar los datos consolidados en la vista utilizando el indice de la cedula
    SELECT * INTO v_asambleista FROM vw_asambleista_hoja_vida WHERE cedula = p_cedula;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró ningún asambleísta con la cédula proporcionada.';
    END IF;

    --  Generar el Folio unico para el certificado 
    v_folio := 'CERT-' || p_cedula || '-' || to_char(now(), 'DDMMYY-HH24MISS');

    -- Registrar la generación en la tabla de auditoria
    INSERT INTO solicitudes_certificacion (cedula_consultada, folio_asignado)
    VALUES (p_cedula, v_folio);

    -- Construye y retorna segun el formato
    RETURN QUERY
    SELECT 
        v_folio,
        to_char(now(), 'DD/MM/YYYY HH24:MI:SS TZR'),
        'CERTIFICADO OFICIAL DE HOJA DE VIDA' || CHR(10) ||
        '==========================================' || CHR(10) ||
        'Folio de Verificación: ' || v_folio || CHR(10) ||
        'Fecha de Emisión: ' || to_char(now(), 'DD/MM/YYYY HH24:MI:SS') || CHR(10) ||
        '==========================================' || CHR(10) || CHR(10) ||
        'Por medio de la presente se da fe de las ejecutorias del legislador:' || CHR(10) || CHR(10) ||
        'Nombre Completo: ' || v_asambleista.nombre_completo || CHR(10) ||
        'Cédula de Identidad: ' || v_asambleista.cedula || CHR(10) ||
        'Periodos de Gestión: ' || v_asambleista.periodos_gestion || CHR(10) ||
        'Porcentaje de Asistencia: ' || v_asambleista.porcentaje_asistencia || '%' || CHR(10) || CHR(10) ||
        'PROPUESTAS Y REFORMAS ASOCIADAS:' || CHR(10) ||
        v_asambleista.lista_propuestas || CHR(10) || CHR(10) ||
        '==========================================' || CHR(10) ||
        'Documento generado de forma automática. Cuenta con trazabilidad digital.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

