import 'package:flutter/material.dart';

class ToolSettingsMenu extends StatefulWidget {
  final Color initialColor;
  final double initialThickness;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onThicknessChanged;

  const ToolSettingsMenu({
    Key? key,
    required this.initialColor,
    required this.initialThickness,
    required this.onColorSelected,
    required this.onThicknessChanged,
  }) : super(key: key);

  @override
  _ToolSettingsMenuState createState() => _ToolSettingsMenuState();
}

class _ToolSettingsMenuState extends State<ToolSettingsMenu> {
  late Color _selectedColor;
  late double _thickness;

  // La palette di colori ispirata alla tua foto
  final List<Color> _palette = [
    Colors.black,
    Color(0xFF3949AB), // Blu scuro/Indaco
    Color(0xFFE53935), // Rosso
    Color(0xFF795548), // Marrone
    Color(0xFF8E24AA), // Viola
    Color(0xFF1E88E5), // Azzurro
    Color(0xFF26A69A), // Verde acqua
    Color(0xFFFFB300), // Giallo scuro
    Color(0xFFFB8C00), // Arancione
    Colors.white,
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _thickness = widget.initialThickness;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320, // Larghezza fissa per il menu a tendina
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D2D), // Sfondo scuro elegante
        borderRadius: BorderRadius.circular(16), // Bordi arrotondati su tutti i lati
        boxShadow: [
          BoxShadow(color: Colors.black38, blurRadius: 12, spreadRadius: 2, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- SELEZIONE COLORE ---
          Text("Palette Colori", style: TextStyle(color: Colors.white70, fontSize: 14)),
          SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _palette.map((color) {
                bool isSelected = _selectedColor.value == color.value;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedColor = color);
                    widget.onColorSelected(color);
                  },
                  child: Container(
                    margin: EdgeInsets.only(right: 12),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.blueAccent : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        if (color == Colors.black || color == Colors.white)
                          BoxShadow(color: Colors.black26, blurRadius: 2)
                      ],
                    ),
                    child: isSelected 
                        ? Icon(Icons.keyboard_arrow_down, 
                            color: color == Colors.white ? Colors.black : Colors.white, 
                            size: 20) 
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
          
          SizedBox(height: 24),
          Divider(color: Colors.grey.shade700),
          SizedBox(height: 16),

          // --- SLIDER SPESSORE ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Spessore del pennello", style: TextStyle(color: Colors.white, fontSize: 16)),
              Text(_thickness.toStringAsFixed(1), style: TextStyle(color: Colors.white70)),
            ],
          ),
          SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade600,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
              trackHeight: 4.0,
            ),
            child: Slider(
              value: _thickness,
              min: 0.5,
              max: 10.0,
              divisions: 38,
              onChanged: (value) {
                setState(() => _thickness = value);
                widget.onThicknessChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}