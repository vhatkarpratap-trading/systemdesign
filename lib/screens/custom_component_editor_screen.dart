import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/custom_component.dart';
import '../models/component.dart';
import '../models/connection.dart';
import '../providers/custom_component_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/canvas/drawing_toolbar.dart';
import '../providers/game_provider.dart';

/// Screen for creating and editing custom components
class CustomComponentEditorScreen extends ConsumerStatefulWidget {
  final String? componentId; // null for new component

  const CustomComponentEditorScreen({super.key, this.componentId});

  @override
  ConsumerState<CustomComponentEditorScreen> createState() => _CustomComponentEditorScreenState();
}

class _CustomComponentEditorScreenState extends ConsumerState<CustomComponentEditorScreen> {
  late CustomComponentDefinition _component;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final _uuid = const Uuid();
  
  String? _selectedNodeId;
  String? _connectingFromNodeId;
  bool _isConnecting = false;
  CanvasTool _activeTool = CanvasTool.select;
  
  // Drawing state
  Offset? _drawStartPos;
  Offset? _drawEndPos;
  
  // Canvas state
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _initComponent();
  }

  void _initComponent() {
    if (widget.componentId != null) {
      final existing = ref.read(customComponentProvider.notifier).getById(widget.componentId!);
      if (existing != null) {
        _component = existing;
      } else {
        _component = CustomComponentDefinition.empty();
      }
    } else {
      _component = CustomComponentDefinition.empty();
    }
    _nameController.text = _component.name;
    _descriptionController.text = _component.description;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _saveComponent() {
    final updated = _component.copyWith(
      name: _nameController.text,
      description: _descriptionController.text,
    );
    ref.read(customComponentProvider.notifier).save(updated);
    setState(() => _component = updated);
  }

  void _addInternalNode(ComponentType type, {Offset? position, Size? size}) {
    final newNode = InternalNode(
      id: _uuid.v4(),
      label: type.displayName,
      type: type,
      relativePosition: position ?? Offset(100 + _component.internalNodes.length * 50, 100 + _component.internalNodes.length * 30),
      size: size ?? const Size(120, 80),
      config: ComponentConfig.defaultFor(type),
    );
    
    setState(() {
      _component = _component.copyWith(
        internalNodes: [..._component.internalNodes, newNode],
      );
    });
    _saveComponent();
  }

  void _removeInternalNode(String nodeId) {
    setState(() {
      _component = _component.copyWith(
        internalNodes: _component.internalNodes.where((n) => n.id != nodeId).toList(),
        internalConnections: _component.internalConnections
            .where((c) => c.sourceNodeId != nodeId && c.targetNodeId != nodeId)
            .toList(),
        inputPorts: _component.inputPorts.where((p) => p.connectedToNodeId != nodeId).toList(),
        outputPorts: _component.outputPorts.where((p) => p.connectedToNodeId != nodeId).toList(),
      );
    });
    _saveComponent();
  }

  void _startConnecting(String fromNodeId) {
    setState(() {
      _connectingFromNodeId = fromNodeId;
      _isConnecting = true;
    });
  }

  void _completeConnection(String toNodeId) {
    if (_connectingFromNodeId != null && _connectingFromNodeId != toNodeId) {
      final connection = InternalConnection(
        id: _uuid.v4(),
        sourceNodeId: _connectingFromNodeId!,
        targetNodeId: toNodeId,
      );
      setState(() {
        _component = _component.copyWith(
          internalConnections: [..._component.internalConnections, connection],
        );
        _isConnecting = false;
        _connectingFromNodeId = null;
      });
      _saveComponent();
    }
  }

  void _cancelConnecting() {
    setState(() {
      _isConnecting = false;
      _connectingFromNodeId = null;
    });
  }

  void _removeConnection(String connectionId) {
    setState(() {
      _component = _component.copyWith(
        internalConnections: _component.internalConnections
            .where((c) => c.id != connectionId)
            .toList(),
      );
    });
    _saveComponent();
  }

  ComponentType? _getComponentTypeFromTool(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.rectangle: return ComponentType.rectangle;
      case CanvasTool.circle: return ComponentType.circle;
      case CanvasTool.diamond: return ComponentType.diamond;
      case CanvasTool.text: return ComponentType.text;
      case CanvasTool.arrow: return ComponentType.arrow; 
      case CanvasTool.line: return ComponentType.line;
      default: return null;
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (_activeTool == CanvasTool.select && !_isConnecting) {
       setState(() => _selectedNodeId = null);
       return;
    }
    
    if (_isConnecting) {
      _cancelConnecting();
      return;
    }

    final type = _getComponentTypeFromTool(_activeTool);
    if (type != null) {
      _addInternalNode(type, position: details.localPosition);
      setState(() => _activeTool = CanvasTool.select);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
           content: Text('Added ${type.displayName}'),
           duration: const Duration(milliseconds: 500),
        )
      );
    }
  }

  void _updateNodePosition(String nodeId, Offset delta) {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final adjustedDelta = delta / scale;
    
    setState(() {
      _component = _component.copyWith(
        internalNodes: _component.internalNodes.map((n) {
          if (n.id == nodeId) {
            return n.copyWith(relativePosition: n.relativePosition + adjustedDelta);
          }
          return n;
        }).toList(),
      );
    });
  }

  void _addInputPort(String nodeId) {
    final node = _component.internalNodes.firstWhere((n) => n.id == nodeId);
    final port = Port(
      id: _uuid.v4(),
      name: 'Input ${_component.inputPorts.length + 1}',
      direction: PortDirection.input,
      connectedToNodeId: nodeId,
    );
    setState(() {
      _component = _component.copyWith(
        inputPorts: [..._component.inputPorts, port],
      );
    });
    _saveComponent();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added input port connected to ${node.label}')),
    );
  }

  void _addOutputPort(String nodeId) {
    final node = _component.internalNodes.firstWhere((n) => n.id == nodeId);
    final port = Port(
      id: _uuid.v4(),
      name: 'Output ${_component.outputPorts.length + 1}',
      direction: PortDirection.output,
      connectedToNodeId: nodeId,
    );
    setState(() {
      _component = _component.copyWith(
        outputPorts: [..._component.outputPorts, port],
      );
    });
    _saveComponent();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added output port connected to ${node.label}')),
    );
  }

  void _publishComponent() {
    setState(() {
      _component = _component.copyWith(isPublished: true);
    });
    ref.read(customComponentProvider.notifier).save(_component);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎉 Component published! Now available in your palette.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _exportToJson() {
    final json = _component.toJsonString();
    Clipboard.setData(ClipboardData(text: json));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('JSON copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Row(
          children: [
            Icon(_component.icon, color: _component.color),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Component Name',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
                onChanged: (_) => _saveComponent(),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Export JSON',
            onPressed: _exportToJson,
          ),
          if (!_component.isPublished)
            TextButton.icon(
              icon: const Icon(Icons.publish, color: Colors.green),
              label: const Text('Publish', style: TextStyle(color: Colors.green)),
              onPressed: _component.internalNodes.isNotEmpty ? _publishComponent : null,
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Chip(
                label: Text('Published'),
                backgroundColor: Colors.green,
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          // Left: Component Palette
          _buildPalette(),
          
          // Center: Canvas
          Expanded(
            child: _buildCanvas(),
          ),
          
          // Right: Properties Panel
          _buildPropertiesPanel(),
        ],
      ),
    );
  }

  Widget _buildPalette() {
    final paletteTypes = [
      ComponentType.appServer,
      ComponentType.database,
      ComponentType.cache,
      ComponentType.queue,
      ComponentType.loadBalancer,
      ComponentType.apiGateway,
      ComponentType.worker,
      ComponentType.pubsub,
      ComponentType.shardNode,
      ComponentType.partitionNode,
      ComponentType.replicaNode,
      ComponentType.inputNode,
      ComponentType.outputNode,
    ];

    return Container(
      width: 180,
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Add Internal Node',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: paletteTypes.length,
              itemBuilder: (context, index) {
                final type = paletteTypes[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PaletteItem(
                    type: type,
                    onTap: () => _addInternalNode(type),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas() {
    return Stack(
      children: [
        Container(
          color: AppTheme.background,
          child: InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1,
            maxScale: 5.0,
            constrained: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _handleTapUp,
              onPanStart: (details) {
                 if (_activeTool != CanvasTool.select && _activeTool != CanvasTool.hand && _activeTool != CanvasTool.eraser) {
                   setState(() {
                     _drawStartPos = details.localPosition;
                     _drawEndPos = details.localPosition;
                   });
                 }
              },
              onPanUpdate: (details) {
                if (_drawStartPos != null) {
                   setState(() {
                     _drawEndPos = details.localPosition;
                   });
                }
              },
              onPanEnd: (details) {
                 if (_drawStartPos != null && _drawEndPos != null) {
                   final rect = Rect.fromPoints(_drawStartPos!, _drawEndPos!);
                   final type = _getComponentTypeFromTool(_activeTool);
                   
                   if (type != null && rect.size.width > 5 && rect.size.height > 5) {
                     _addInternalNode(type, position: rect.topLeft, size: rect.size);
                     setState(() {
                       _activeTool = CanvasTool.select;
                       _drawStartPos = null; 
                       _drawEndPos = null;
                     });
                   } else {
                      // Too small, treat as tap or cancel
                      setState(() { 
                        _drawStartPos = null; 
                        _drawEndPos = null; 
                      });
                   }
                 }
              },
              child: Container(
                width: 4000,
                height: 4000,
                color: AppTheme.background,
                child: Stack(
                  children: [
                    // Grid background
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GridPainter(),
                      ),
                    ),
                    
                    // Connections
                    ..._component.internalConnections.map((conn) {
                      final source = _component.internalNodes.firstWhere(
                        (n) => n.id == conn.sourceNodeId,
                        orElse: () => _component.internalNodes.first,
                      );
                      final target = _component.internalNodes.firstWhere(
                        (n) => n.id == conn.targetNodeId,
                        orElse: () => _component.internalNodes.first,
                      );
                      return _ConnectionLine(
                        start: source.relativePosition + const Offset(60, 30),
                        end: target.relativePosition + const Offset(60, 30),
                        onDelete: () => _removeConnection(conn.id),
                      );
                    }),
                    
                    // Internal Nodes
                    ..._component.internalNodes.map((node) => _InternalNodeWidget(
                      node: node,
                      isSelected: _selectedNodeId == node.id,
                      isConnecting: _isConnecting,
                      isConnectingSource: _connectingFromNodeId == node.id,
                      hasInputPort: _component.inputPorts.any((p) => p.connectedToNodeId == node.id),
                      hasOutputPort: _component.outputPorts.any((p) => p.connectedToNodeId == node.id),
                      onTap: () {
                        if (_activeTool == CanvasTool.eraser) {
                          _removeInternalNode(node.id);
                          return;
                        }
                        if (_isConnecting) {
                          _completeConnection(node.id);
                        } else {
                          setState(() => _selectedNodeId = node.id);
                        }
                      },
                      onDragUpdate: (delta) => _updateNodePosition(node.id, delta),
                      onDragEnd: () => _saveComponent(),
                      onStartConnect: () => _startConnecting(node.id),
                      onDelete: () => _removeInternalNode(node.id),
                      onAddInputPort: () => _addInputPort(node.id),
                      onAddOutputPort: () => _addOutputPort(node.id),
                    )),
                    
                    // Drawing Preview
                    if (_drawStartPos != null && _drawEndPos != null)
                      Positioned(
                        left: Rect.fromPoints(_drawStartPos!, _drawEndPos!).left,
                        top: Rect.fromPoints(_drawStartPos!, _drawEndPos!).top,
                        child: Container(
                          width: Rect.fromPoints(_drawStartPos!, _drawEndPos!).width,
                          height: Rect.fromPoints(_drawStartPos!, _drawEndPos!).height,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.primary, width: 1),
                            color: AppTheme.primary.withOpacity(0.1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        
        // Connecting mode indicator
        if (_isConnecting)
          Positioned(
            bottom: 80, // Moved up to make room for toolbar
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Click another node to connect, or tap canvas to cancel',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          
        // Drawing Toolbar
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: DrawingToolbar(
              activeTool: _activeTool,
              onToolChanged: (tool) => setState(() => _activeTool = tool),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPropertiesPanel() {
    return Container(
      width: 280,
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Description
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Description',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Describe what this component does...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) => _saveComponent(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          
          // Ports Summary
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ports',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._component.inputPorts.map((p) => _PortChip(
                  port: p,
                  isInput: true,
                  nodeName: _component.internalNodes
                      .firstWhere((n) => n.id == p.connectedToNodeId, orElse: () => _component.internalNodes.first)
                      .label,
                )),
                ..._component.outputPorts.map((p) => _PortChip(
                  port: p,
                  isInput: false,
                  nodeName: _component.internalNodes
                      .firstWhere((n) => n.id == p.connectedToNodeId, orElse: () => _component.internalNodes.first)
                      .label,
                )),
                if (_component.inputPorts.isEmpty && _component.outputPorts.isEmpty)
                  const Text(
                    'No ports defined yet.\nSelect a node and add input/output ports.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          
          // Stats
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _StatRow(label: 'Internal Nodes', value: '${_component.internalNodes.length}'),
                _StatRow(label: 'Connections', value: '${_component.internalConnections.length}'),
                _StatRow(label: 'Input Ports', value: '${_component.inputPorts.length}'),
                _StatRow(label: 'Output Ports', value: '${_component.outputPorts.length}'),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Selected node actions
          if (_selectedNodeId != null)
            _buildSelectedNodeActions(),
        ],
      ),
    );
  }

  Widget _buildSelectedNodeActions() {
    final node = _component.internalNodes.firstWhere(
      (n) => n.id == _selectedNodeId,
      orElse: () => _component.internalNodes.first,
    );
    
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.primary.withOpacity(0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected: ${node.label}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.input, size: 16),
                  label: const Text('+ Input'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _addInputPort(node.id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.output, size: 16),
                  label: const Text('+ Output'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _addOutputPort(node.id),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Connect to...'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () => _startConnecting(node.id),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Helper Widgets ---

class _PaletteItem extends StatelessWidget {
  final ComponentType type;
  final VoidCallback onTap;

  const _PaletteItem({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(type.icon, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  type.displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              const Icon(Icons.add, color: Colors.white38, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _InternalNodeWidget extends StatelessWidget {
  final InternalNode node;
  final bool isSelected;
  final bool isConnecting;
  final bool isConnectingSource;
  final bool hasInputPort;
  final bool hasOutputPort;
  final VoidCallback onTap;
  final Function(Offset) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onStartConnect;
  final VoidCallback onDelete;
  final VoidCallback onAddInputPort;
  final VoidCallback onAddOutputPort;

  const _InternalNodeWidget({
    required this.node,
    required this.isSelected,
    required this.isConnecting,
    required this.isConnectingSource,
    required this.hasInputPort,
    required this.hasOutputPort,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onStartConnect,
    required this.onDelete,
    required this.onAddInputPort,
    required this.onAddOutputPort,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: node.relativePosition.dx,
      top: node.relativePosition.dy,
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main node content based on type
            if (node.type == ComponentType.circle)
              Container(
                width: node.size.width,
                height: node.size.height,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary.withOpacity(0.3) : AppTheme.surface.withOpacity(0.5),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(node.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              )
            else if (node.type == ComponentType.rectangle)
              Container(
                width: node.size.width,
                height: node.size.height,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary.withOpacity(0.3) : AppTheme.surface.withOpacity(0.5),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(node.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              )
            else if (node.type == ComponentType.diamond)
              Transform.rotate(
                angle: 0.785398, // 45 degrees
                child: Container(
                  width: node.size.width, // Assuming square for diamond usually, but using width
                  height: node.size.width,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primary.withOpacity(0.3) : AppTheme.surface.withOpacity(0.5),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Transform.rotate(
                    angle: -0.785398,
                    child: Center(
                      child: Text(node.label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ),
              )
             else if (node.type == ComponentType.text)
               Container(
                 padding: const EdgeInsets.all(8),
                 decoration: isSelected ? BoxDecoration(
                   border: Border.all(color: AppTheme.primary, width: 1, style: BorderStyle.solid),
                   borderRadius: BorderRadius.circular(4),
                 ) : null,
                 child: Text(
                   node.label, 
                   style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
                 ),
               )
             else if (node.type == ComponentType.line)
               Container(
                 width: node.size.width,
                 height: 4,
                 decoration: BoxDecoration(
                   color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                   borderRadius: BorderRadius.circular(2),
                   boxShadow: isSelected ? [
                     BoxShadow(color: AppTheme.primary.withOpacity(0.5), blurRadius: 4)
                   ] : null,
                 ),
               )
             else if (node.type == ComponentType.arrow)
               Icon(
                 Icons.arrow_forward_rounded, 
                 size: node.size.width > 40 ? node.size.width : 40, 
                 color: isSelected ? AppTheme.primary : AppTheme.textMuted
               )
            else
              // Default Container for Standard Components
              Container(
                width: 120,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? AppTheme.primary.withOpacity(0.3) 
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected 
                        ? AppTheme.primary 
                        : isConnecting && !isConnectingSource
                            ? Colors.green
                            : Colors.white24,
                    width: isSelected || (isConnecting && !isConnectingSource) ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(node.type.icon, color: AppTheme.primary, size: 28),
                    const SizedBox(height: 4),
                    Text(
                      node.label,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            
            // Delete button (common)
            if (isSelected)
              Positioned(
                right: -8,
                top: -8,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 12),
                  ),
                ),
              ),
            
            // Input port indicator
            if (hasInputPort)
              Positioned(
                left: -8,
                top: 25,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.arrow_right, color: Colors.white, size: 10),
                ),
              ),
            
            // Output port indicator
            if (hasOutputPort)
              Positioned(
                right: -8,
                top: 25,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.arrow_right, color: Colors.white, size: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionLine extends StatelessWidget {
  final Offset start;
  final Offset end;
  final VoidCallback onDelete;

  const _ConnectionLine({
    required this.start,
    required this.end,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _ConnectionPainter(start: start, end: end),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _ConnectionPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withOpacity(0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(start.dx, start.dy);
    
    // Bezier curve for smooth connection
    final midX = (start.dx + end.dx) / 2;
    path.cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
    
    canvas.drawPath(path, paint);
    
    // Draw arrowhead
    final arrowPaint = Paint()
      ..color = AppTheme.primary.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    
    final angle = (end - start).direction;
    const arrowSize = 10.0;
    
    final arrowPath = Path();
    arrowPath.moveTo(end.dx, end.dy);
    arrowPath.lineTo(
      end.dx - arrowSize * 1.5 * (end.dx > start.dx ? 1 : -1),
      end.dy - arrowSize / 2,
    );
    arrowPath.lineTo(
      end.dx - arrowSize * 1.5 * (end.dx > start.dx ? 1 : -1),
      end.dy + arrowSize / 2,
    );
    arrowPath.close();
    
    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) {
    return start != oldDelegate.start || end != oldDelegate.end;
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    const gridSize = 50.0;
    
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PortChip extends StatelessWidget {
  final Port port;
  final bool isInput;
  final String nodeName;

  const _PortChip({
    required this.port,
    required this.isInput,
    required this.nodeName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isInput ? Colors.blue.withOpacity(0.2) : Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isInput ? Colors.blue : Colors.orange,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isInput ? Icons.input : Icons.output,
              color: isInput ? Colors.blue : Colors.orange,
              size: 14,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '${port.name} → $nodeName',
                style: TextStyle(
                  color: isInput ? Colors.blue : Colors.orange,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
