/// Stable tool identities shared by models, controllers and UI.
enum EditingTool {
  STYLUS,
  HIGHLIGHT,
  TEXT,
  LATEX,
  IMAGE,
  MOVE,
  SELECT,
  FLASHCARD,
  ERASER,
  WHITEOUT,
  SHAPE_LINE,
  SHAPE_RECT,
  SHAPE_CIRCLE,
  SHAPE_SQUARE,
  SHAPE_DASHED_LINE,
  SHAPE_CUBE,
  SHAPE_CYLINDER,
  SHAPE_SPHERE,
  SHAPE_AXES,
}

extension ShapeTool on EditingTool {
  bool get isShape => name.startsWith('SHAPE_');
}
