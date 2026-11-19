# Gates: личный Homepage
OWNS: **
Scope: закрытый редактор и изолированный пакет
- [ ] G1: Запись переживает перезапуск, конфликт и отказ записи сохраняют предыдущее содержимое
  CHECK: node --test personal/store.test.mjs
  EXPECT: fail 0
  EVIDENCE: pending
- [x] G2: Вход, CRUD и выход работают в браузере на настольном и узком экране
  EVIDENCE: Chrome on macOS, 390px viewport and desktop. Verified sign-in denial, CRUD, refresh, restart, revision conflict, cancellation, logout replay.
- [ ] G3: Установка из пакета изолирует данные, порт и жизненный цикл приложения
  EVIDENCE: pending
- [ ] G4: Повторное открытие установщика позволяет продолжить с готового образа или конфигурации
  EVIDENCE: pending
- [ ] G5: Место, зависимости и порты проверяются до сборки
  EVIDENCE: pending
- [ ] G6: Пункт 2 добавляет отдельно отсутствующий CLI-плагин
  EVIDENCE: pending
- [ ] Публичная команда скачивает установщик и сохраняет прежний файл при ошибке.
  EVIDENCE: pending
