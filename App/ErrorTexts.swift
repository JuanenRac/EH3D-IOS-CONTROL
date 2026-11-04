// EH3D-IOS-CONTROL - the text for each refusal code of the server that the app can meet, in the language of the app.
// The codes are the ones of docs/error-codes.json of EH3D-SERVER; the tests of the package check that no code of that catalog is left without a text or a reason.
// Copyright (C) 2026 JuanenRac (Electro Hobby 3D). GPL-3.0-or-later.
import Foundation

extension AppModel {
    /// The words for a refusal code, or nil when the app has none and shows the message of the server.
    func refusalText(_ code: String) -> String? {
        switch code {
        case "bad_address": return tr("Un nodo necesita su dirección (host:puerto).")
        case "bad_cfg": return tr("La configuración tiene una clave que no existe o un valor fuera de rango.")
        case "bad_days": return tr("Los días deben ser un número de 1 a 3650.")
        case "bad_gcode": return tr("El programa tiene una línea que no es G-code: los ajustes y órdenes en tiempo real del controlador ($, !, ~, ?), los caracteres de control y las líneas de más de 200 caracteres se rechazan.")
        case "bad_id": return tr("El id debe ser letras minúsculas, dígitos y guiones, hasta 32 caracteres.")
        case "bad_light": return tr("Al anillo de LEDs se le pidió algo que el nodo no usa (un nivel, un tono o sectores que no conoce).")
        case "bad_request": return tr("El servidor no aceptó lo enviado.")
        case "bad_station": return tr("La estación debe ser letras minúsculas, dígitos y guiones, hasta 32 caracteres.")
        case "forbidden": return tr("Tu rol no permite esto.")
        case "head_refused": return tr("El nodo del cabezal de taladro rechazó la petición (comprueba su token en la configuración de la máquina).")
        case "internal": return tr("El servidor falló con esta petición. Inténtelo de nuevo.")
        case "job_active": return tr("El trabajo está en marcha: páralo primero.")
        case "last_admin": return tr("El último administrador no se puede borrar, desactivar ni degradar.")
        case "local_only": return tr("Este servidor aún no tiene usuarios: cree el administrador desde el ordenador en el que funciona.")
        case "machine_exists": return tr("Ya existe una máquina con ese id.")
        case "machines_busy": return tr("Hay un trabajo en marcha: actualizar reinicia el servidor y lo detendría. Espera a que termine.")
        case "not_cancellable": return tr("El trabajo no se puede cancelar en su estado actual.")
        case "not_ready": return tr("El trabajo no está listo para empezar (puede haberse cancelado o empezado ya).")
        case "not_running": return tr("El trabajo no está en marcha.")
        case "out_of_table": return tr("El trabajo sale de la mesa de la máquina.")
        case "storage": return tr("El servidor no pudo escribir sus datos. Revise el disco.")
        case "too_big": return tr("El trabajo es demasiado grande (más de un millón de líneas, o más de lo que admite el servidor).")
        case "unauthorized": return tr("El nombre o la contraseña no son correctos, o la sesión ha terminado.")
        case "unknown_job": return tr("Ese trabajo no existe.")
        case "unknown_machine": return tr("Esa máquina no existe.")
        case "unknown_token": return tr("No existe ese token.")
        case "unknown_user": return tr("Ese usuario no existe.")
        case "update_refused": return tr("El asistente de actualización rechazó la petición.")
        case "updates_off": return tr("Las actualizaciones no están configuradas en este servidor.")
        case "user_exists": return tr("Ese usuario ya existe.")
        case "wrong_machine": return tr("Esta máquina no admite este tipo de trabajo: un nodo admite taladrado y fresado, una máquina GRBL admite G-code y el simulador admite los tres.")
        default: return nil
        }
    }
}
