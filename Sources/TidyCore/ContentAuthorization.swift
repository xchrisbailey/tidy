import Foundation

func authorizesContentNaming(_ evidence: String) -> Bool {
  let text = metadataInstructionText(evidence)
  let naming = [
    "name", "names", "filename", "filenames", "rename", "renaming", "nombres", "renombrar",
    "renombra", "noms", "renommer", "nennen", "umbenennen", "dateinamen", "nomi", "rinomina",
    "nomes", "renomear",
  ]
  let content = [
    "content", "contents", "text", "readable", "useful", "recognizable", "meaningful",
    "contenido", "contenidos", "legibles", "contenu", "lisibles", "inhalt", "lesbare",
    "contenuto", "leggibili", "conteúdo", "legíveis",
  ]
  return containsWord(text, naming) && containsWord(text, content)
    || (["重命名", "ファイル名", "이름"].contains(where: text.contains)
      && ["内容", "読みやす", "내용"].contains(where: text.contains))
}
