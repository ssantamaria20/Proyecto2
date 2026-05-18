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

-- Creacion de la tabla de Nombramientos con control de vigencia (Issue 15)
CREATE TABLE nombramientos (
    id_nombramiento SERIAL PRIMARY KEY,
    cedula_asambleista VARCHAR(50) REFERENCES asambleistas(cedula) ON DELETE CASCADE,
    puesto VARCHAR(150) NOT NULL,
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    activo BOOLEAN DEFAULT TRUE 
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
