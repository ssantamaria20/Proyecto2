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