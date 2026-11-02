DROP DATABASE IF EXISTS MatriculaUniversitaria;
CREATE DATABASE MatriculaUniversitaria;
USE MatriculaUniversitaria;

CREATE TABLE Estudiantes (
    estudiante_id  INT AUTO_INCREMENT NOT NULL,
    nombre         VARCHAR(100)       NOT NULL,
    cedula         CHAR(10)           NOT NULL,
    facultad       VARCHAR(80)        NOT NULL,
    PRIMARY KEY (estudiante_id),
    UNIQUE KEY UQ_Estudiantes_Cedula (cedula),
    CONSTRAINT CK_Estudiantes_Cedula CHECK (LENGTH(cedula) = 10 AND cedula REGEXP '^[0-9]+$')
);

CREATE TABLE Asignaturas (
    asignatura_id      INT AUTO_INCREMENT NOT NULL,
    nombre_materia     VARCHAR(100)       NOT NULL,
    docente            VARCHAR(100)       NOT NULL,
    cupos_disponibles  SMALLINT           NOT NULL DEFAULT 0,
    PRIMARY KEY (asignatura_id),
    UNIQUE KEY UQ_Asignaturas_Nombre (nombre_materia),
    CONSTRAINT CK_Asignaturas_Cupos CHECK (cupos_disponibles >= 0)
);

CREATE TABLE Registros_Matricula (
    registro_id     INT AUTO_INCREMENT NOT NULL,
    estudiante_id   INT                NOT NULL,
    asignatura_id   INT                NOT NULL,
    fecha_registro  DATETIME           NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado          VARCHAR(10)        NOT NULL DEFAULT 'PENDIENTE',
    PRIMARY KEY (registro_id),
    CONSTRAINT FK_Registros_Estudiante FOREIGN KEY (estudiante_id) REFERENCES Estudiantes (estudiante_id),
    CONSTRAINT FK_Registros_Asignatura FOREIGN KEY (asignatura_id) REFERENCES Asignaturas (asignatura_id),
    CONSTRAINT CK_Registros_Estado CHECK (estado IN ('CONFIRMADA', 'PENDIENTE')),
    CONSTRAINT UQ_Registros_Estudiante_Asignatura UNIQUE (estudiante_id, asignatura_id)
);

CREATE INDEX IX_Registros_Asignatura ON Registros_Matricula (asignatura_id, estado);

-- ==========================================
-- 1.3 DATOS INICIALES (Incluye datos para transacciones)
-- ==========================================
INSERT INTO Estudiantes (nombre, cedula, facultad) VALUES 
('Ana Torres', '0601000001', 'Ingeniería'),
('Luis Paredes', '0601000002', 'Ingeniería'),
('María Guamán', '0601000003', 'Ciencias'),
('Jorge Cevallos', '0601000004', 'Salud'),
('Sofía Yépez', '0601000005', 'Ciencias'),
('Diego Andrade', '0601000006', 'Ingeniería');

INSERT INTO Asignaturas (nombre_materia, docente, cupos_disponibles) VALUES 
('Base de Datos', 'Ing. Paúl Ramírez', 30),
('Machine Learning', 'Ing. Elena Villacrés', 25),
('Métodos Numéricos', 'Ing. Marco Silva', 20),
('Inteligencia Artificial', 'Ing. Rosa Lema', 5),
('Ética Profesional', 'Dra. Carmen Ortiz', 0);

-- Matrículas previas (Jorge en Ética 0 cupos, Sofía en IA)
INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES 
(4, 5, 'CONFIRMADA'),
(5, 4, 'CONFIRMADA');

SELECT * FROM Estudiantes;
SELECT * FROM Asignaturas;
SELECT * FROM Registros_Matricula;

-- ==========================================
-- 2. TRANSACCIONES ACID
-- ==========================================

-- TRANSACCIÓN A: Matrícula completa (COMMIT)
SET @idBD = (SELECT asignatura_id FROM Asignaturas WHERE nombre_materia = 'Base de Datos');
START TRANSACTION;
    INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (1, @idBD, 'CONFIRMADA');
    UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = @idBD;
    -- Verificamos transacción abierta (equivalente a @@TRANCOUNT)
    SELECT @@in_transaction AS transacciones_abiertas; 
COMMIT;
SELECT @@in_transaction AS transacciones_abiertas_tras_commit;
-- Verificación A
SELECT * FROM Registros_Matricula WHERE estudiante_id = 1;
SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = @idBD;  -- 29

-- TRANSACCIÓN B: Fallo y ROLLBACK (Luis)
START TRANSACTION;
    INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (2, 1, 'PENDIENTE');
    -- El INSERT es visible
    SELECT * FROM Registros_Matricula WHERE estudiante_id = 2;
    
    -- Forzar error (CHECK constraint de cupos >= 0)
    UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 999 WHERE asignatura_id = 1;
    
    -- Verificamos que sigue abierta tras el error
    SELECT @@in_transaction AS transacciones_abiertas_tras_error;
ROLLBACK;
-- Verificación final
SELECT * FROM Registros_Matricula WHERE estudiante_id = 2;          -- 0 filas
SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 1;  -- 29

-- TRANSACCIÓN C: Todo o nada (María)
DELIMITER //
CREATE PROCEDURE sp_MatriculaMultiple()
BEGIN
    DECLARE v_error_code VARCHAR(10);
    DECLARE v_error_msg VARCHAR(255);
    
    -- Manejador de errores (Equivalente a TRY...CATCH)
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_code = RETURNED_SQLSTATE, v_error_msg = MESSAGE_TEXT;
        ROLLBACK;
        SELECT v_error_code AS error_n, v_error_msg AS mensaje, 'ROLLBACK ejecutado' AS accion;
    END;

    START TRANSACTION;
        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 2;
        INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (3, 2, 'CONFIRMADA');
        
        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 3;
        INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (3, 3, 'CONFIRMADA');
        
        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 999;
        
        -- Equivalente a IF @@ROWCOUNT = 0 THROW...
        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La asignatura 999 no existe. Se cancela toda la matrícula.';
        END IF;
        
        INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (3, 999, 'CONFIRMADA');
    COMMIT;
END //
DELIMITER ;

CALL sp_MatriculaMultiple();
-- Verificación: Machine Learning sigue en 25, Métodos Numéricos en 20 y María sin matrículas
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas WHERE asignatura_id IN (2, 3);
SELECT * FROM Registros_Matricula WHERE estudiante_id = 3;


-- ==========================================
-- 3. PRUEBAS DE BLOQUEOS Y NIVELES DE AISLAMIENTO
-- Abrir DOS ventanas (sesiones) conectadas a MatriculaUniversitaria.
-- [S1] = Ventana 1, [S2] = Ventana 2. Ejecutar en el orden T1, T2, ...
-- Preparación en ambas ventanas:
--   USE MatriculaUniversitaria;
--   SELECT CONNECTION_ID();                      -- números distintos en S1 y S2
--   SET SESSION innodb_lock_wait_timeout = 120;  -- tiempo para tomar capturas
-- ==========================================

-- 3.1 READ UNCOMMITTED (Lectura sucia)
-- T1 [S2]: SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
-- T2 [S1]: START TRANSACTION;
--          DELETE FROM Registros_Matricula WHERE estudiante_id = 4 AND asignatura_id = 5;
--          UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles + 1 WHERE asignatura_id = 5;
--          -- (No hacer COMMIT)
-- T3 [S2]: SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 5;          -- Verá 1 (lectura sucia)
--          SELECT * FROM Registros_Matricula WHERE asignatura_id = 5;                   -- 0 filas (no ve a Jorge)
-- T4 [S1]: ROLLBACK;                                                                    -- Jorge desiste del retiro
-- T5 [S2]: SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 5;          -- Vuelve a 0
--          SELECT * FROM Registros_Matricula WHERE asignatura_id = 5;                   -- Jorge vuelve a aparecer

-- 3.2 READ COMMITTED (Lectura no repetible)
-- T1 [S2]: SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
--          START TRANSACTION;
--          SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4;          -- 5
-- T2 [S1]: START TRANSACTION;
--          UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 4;
--          -- (No hacer COMMIT)
-- T3 [S2]: SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4;          -- 5, NO espera (MVCC)
-- T4 [S1]: COMMIT;
-- T5 [S2]: SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4;          -- 4 (cambió dentro de la misma transacción)
--          COMMIT;

-- 3.3 REPEATABLE READ
-- Parte A: lectura consistente (la lectura simple NO bloquea)
-- T1 [S1]: SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--          START TRANSACTION;
--          SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4;          -- 4
-- T2 [S2]: UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 4;  -- Se completa sin esperar (3)
-- T3 [S1]: SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4;          -- Sigue viendo 4
--          COMMIT;
--          SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4;          -- Ahora ve 3
-- Parte B: bloqueo de lectura explícito (FOR SHARE)
-- T4 [S1]: START TRANSACTION;
--          SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4 FOR SHARE; -- 3 y bloquea la fila
-- T5 [S2]: UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 4;  -- ESPERA
-- T6 (opcional, Ventana 3): ejecutar la consulta de monitoreo de la sección 4.4
-- T7 [S1]: COMMIT;                                                                      -- S2 se libera: queda 2

-- 3.4 SERIALIZABLE (Bloqueo de rango)
-- T1 [S1]: SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
--          START TRANSACTION;
--          SELECT * FROM Registros_Matricula WHERE asignatura_id = 4;                  -- 1 fila (Sofía) y bloquea el rango
-- T2 [S2]: INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (6, 4, 'CONFIRMADA');  -- ESPERA
-- T3 [S1]: COMMIT;                                                                      -- S2 se libera y el INSERT se completa
-- T4 [S1]: SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;                    -- volver al nivel por defecto

-- 3.5 DEADLOCK (Interbloqueo)
-- Los dos estudiantes leen el cupo con bloqueo COMPARTIDO y luego ambos intentan descontarlo.
-- T1 [S1]: START TRANSACTION;
--          SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4 FOR SHARE;  -- 2
-- T2 [S2]: START TRANSACTION;
--          SELECT cupos_disponibles FROM Asignaturas WHERE asignatura_id = 4 FOR SHARE;  -- 2 (los bloqueos S son compatibles)
-- T3 [S1]: UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 4;      -- ESPERA a S2
-- T4 [S2]: UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 4;      -- ERROR 1213: Deadlock
-- T5 [S1]: COMMIT;                                                                       -- S1 continúa: queda 1
-- T6 [S1]: SHOW ENGINE INNODB STATUS;   -- sección LATEST DETECTED DEADLOCK (si el usuario tiene privilegio PROCESS)

-- ==========================================
-- 4. PROCEDIMIENTO ALMACENADO MEJORADO (Prevención)
-- ==========================================
DELIMITER //

CREATE PROCEDURE sp_MatricularEstudiante(IN p_estudiante_id INT, IN p_asignatura_id INT)
BEGIN
    DECLARE v_cupos SMALLINT;
    DECLARE v_intento INT DEFAULT 1;
    DECLARE v_error_code VARCHAR(10);
    DECLARE v_error_msg VARCHAR(255);
    
    -- Manejador de errores
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_code = RETURNED_SQLSTATE, v_error_msg = MESSAGE_TEXT;
        ROLLBACK;
        
        -- Deadlock: SQLSTATE 40001 (número de error 1213)
        IF v_error_code = '40001' AND v_intento < 3 THEN
            SET v_intento = v_intento + 1;
            -- En un sistema real aquí habría un bucle WHILE, pero para simplificar mostramos el mensaje.
            SELECT 'Deadlock detectado. Reintentando...' AS accion;
        ELSE
            SELECT CONCAT('Error en matrícula. SQLSTATE ', v_error_code, ': ', v_error_msg) AS accion;
        END IF;
    END;

    START TRANSACTION;
        -- Bloqueo exclusivo (Equivalente a UPDLOCK, HOLDLOCK)
        SELECT cupos_disponibles INTO v_cupos 
        FROM Asignaturas 
        WHERE asignatura_id = p_asignatura_id 
        FOR UPDATE; 
        
        IF v_cupos IS NULL THEN
            SIGNAL SQLSTATE '45010' SET MESSAGE_TEXT = 'La asignatura no existe.';
        END IF;
        
        IF v_cupos <= 0 THEN
            SIGNAL SQLSTATE '45011' SET MESSAGE_TEXT = 'No hay cupos disponibles en la asignatura.';
        END IF;
        
        IF EXISTS (SELECT 1 FROM Registros_Matricula WHERE estudiante_id = p_estudiante_id AND asignatura_id = p_asignatura_id) THEN
            SIGNAL SQLSTATE '45012' SET MESSAGE_TEXT = 'El estudiante ya está matriculado en esta asignatura.';
        END IF;
        
        INSERT INTO Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (p_estudiante_id, p_asignatura_id, 'CONFIRMADA');
        UPDATE Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = p_asignatura_id;
        
    COMMIT;
    SELECT 'Matrícula confirmada.' AS Resultado;
END //
DELIMITER ;

-- Pruebas del procedimiento (Sección 4.2)
CALL sp_MatricularEstudiante(5, 3);    -- Sofía en Métodos Numéricos: confirmada (20 -> 19)
CALL sp_MatricularEstudiante(6, 3);    -- Diego en Métodos Numéricos: confirmada (19 -> 18)
CALL sp_MatricularEstudiante(1, 1);    -- Ana ya está en Base de Datos: SQLSTATE 45012
CALL sp_MatricularEstudiante(1, 999);  -- asignatura inexistente: SQLSTATE 45010
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM Asignaturas;


-- ==========================================
-- 4.4 MONITOREO DE BLOQUEOS (MySQL 8)
-- information_schema.innodb_lock_waits se eliminó en MySQL 8.0;
-- ahora se usa sys.innodb_lock_waits (o performance_schema.data_lock_waits).
-- Ejecutar en una tercera ventana mientras S2 espera (paso 3.3 T6).
-- ==========================================
SELECT
    waiting_trx_id   AS transaccion_espera,
    waiting_pid      AS hilo_espera,
    waiting_query    AS sentencia_detenida,
    blocking_trx_id  AS transaccion_bloquea,
    blocking_pid     AS hilo_bloquea,
    wait_age         AS tiempo_espera
FROM sys.innodb_lock_waits;