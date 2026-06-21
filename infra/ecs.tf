# =========================================================
# ecs.tf - ECS Fargate: cluster, ALB, servicios, autoscaling
# =========================================================
# EP3: orquestacion con ECS Fargate usando LabRole de AWS Academy.
# No se crean roles IAM nuevos (iam:CreateRole bloqueado en Learner Lab).
# =========================================================

# ---- IAM: reutilizar LabRole (no crear roles nuevos) ----
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# =========================================================
# CLUSTER ECS
# =========================================================
resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name_prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# =========================================================
# SECURITY GROUPS para ALB y tareas ECS
# =========================================================
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "ALB publico: acepta HTTP desde internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-alb" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-sg-ecs-tasks"
  description = "Tareas Fargate: acepta trafico solo desde el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg-ecs-tasks" }
}

# =========================================================
# APPLICATION LOAD BALANCER
# =========================================================
resource "aws_lb" "public" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_b.id]

  tags = { Name = "${local.name_prefix}-alb" }
}

# Segunda subred publica necesaria para el ALB (requiere 2 AZs)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = local.azs[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-b"
    Tier = "public"
  }
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ---- Target Groups ----
resource "aws_lb_target_group" "frontend" {
  name        = "${local.name_prefix}-tg-frontend"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.name_prefix}-tg-frontend" }
}

resource "aws_lb_target_group" "ventas" {
  name        = "${local.name_prefix}-tg-ventas"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.name_prefix}-tg-ventas" }
}

resource "aws_lb_target_group" "despachos" {
  name        = "${local.name_prefix}-tg-despachos"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.name_prefix}-tg-despachos" }
}

# ---- Listener y reglas de enrutamiento ----
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.public.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "ventas" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ventas.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/ventas*"]
    }
  }
}

resource "aws_lb_listener_rule" "despachos" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.despachos.arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/despachos*"]
    }
  }
}

# =========================================================
# CLOUDWATCH LOG GROUPS (IE6)
# =========================================================
resource "aws_cloudwatch_log_group" "ventas" {
  name              = "/ecs/${local.name_prefix}-ventas"
  retention_in_days = 7
  tags              = { Name = "/ecs/${local.name_prefix}-ventas" }
}

resource "aws_cloudwatch_log_group" "despachos" {
  name              = "/ecs/${local.name_prefix}-despachos"
  retention_in_days = 7
  tags              = { Name = "/ecs/${local.name_prefix}-despachos" }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name_prefix}-frontend"
  retention_in_days = 7
  tags              = { Name = "/ecs/${local.name_prefix}-frontend" }
}

# =========================================================
# TASK DEFINITIONS
# =========================================================
resource "aws_ecs_task_definition" "ventas" {
  family                   = "${local.name_prefix}-ventas"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # 512/2048: con MaxRAMPercentage=75% el heap queda topado a ~1.5GB,
  # dejando ~512MB para metaspace/threads/code-cache. 256/512 (original)
  # y 512/1024 (primer ajuste) quedaban demasiado ajustados para Spring Boot
  # + Hibernate y causaban OOM kills durante el arranque/bajo carga.
  # Costo extra en Fargate es marginal (~$0.004445/GB-hora).
  cpu                      = "512"
  memory                   = "2048"
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = "ventas"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.name_prefix}-ventas:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "DB_ENDPOINT",   value = aws_instance.database.private_ip },
      { name = "DB_PORT",       value = "3306" },
      { name = "DB_NAME",       value = var.db_name },
      { name = "DB_USERNAME",   value = "root" },
      { name = "DB_PASSWORD",   value = var.db_password },
      { name = "SERVER_PORT",   value = "8080" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ventas.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-ventas" }
}

resource "aws_ecs_task_definition" "despachos" {
  family                   = "${local.name_prefix}-despachos"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  # Mismo razonamiento que ventas: 2048MB le da margen real al JVM.
  cpu                      = "512"
  memory                   = "2048"
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = "despachos"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.name_prefix}-despachos:latest"
    essential = true
    portMappings = [{
      containerPort = 8081
      protocol      = "tcp"
    }]
    environment = [
      { name = "DB_ENDPOINT",   value = aws_instance.database.private_ip },
      { name = "DB_PORT",       value = "3306" },
      { name = "DB_NAME",       value = var.db_name },
      { name = "DB_USERNAME",   value = "root" },
      { name = "DB_PASSWORD",   value = var.db_password },
      { name = "SERVER_PORT",   value = "8081" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.despachos.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-despachos" }
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = data.aws_iam_role.lab_role.arn
  task_role_arn            = data.aws_iam_role.lab_role.arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.name_prefix}-frontend:latest"
    essential = true
    portMappings = [{
      # nginx-unprivileged escucha en 8080, no en 80 (ver Dockerfile front_despacho)
      containerPort = 8080
      protocol      = "tcp"
    }]
    # El listener del ALB ya enruta /api/v1/ventas* y /api/v1/despachos*
    # directo a sus target groups (ver aws_lb_listener_rule mas abajo), asi
    # que el navegador llega a los backends sin pasar por el proxy de nginx
    # (mismo origen: SPA y APIs sirven desde el mismo ALB:80). Estas vars
    # solo evitan que el template de nginx quede con un valor vacio/invalido.
    environment = [
      { name = "VENTAS_HOST",    value = "${aws_lb.public.dns_name}:80" },
      { name = "DESPACHOS_HOST", value = "${aws_lb.public.dns_name}:80" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-frontend" }
}

# Permitir que las tareas ECS se conecten a MySQL en la EC2 database
# (el SG database solo tenia regla desde sg-backend de EC2)
resource "aws_security_group_rule" "db_mysql_from_ecs" {
  type                     = "ingress"
  description              = "MySQL 3306 desde tareas ECS Fargate"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = aws_security_group.ecs_tasks.id
}

# =========================================================
# ECS SERVICES
# =========================================================
resource "aws_ecs_service" "ventas" {
  name            = "${local.name_prefix}-ventas"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.ventas.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Spring Boot tarda en levantar y conectar a MySQL (NAT + cold start JVM).
  # Sin esto, el ALB puede marcar la tarea "unhealthy" y ECS la mata en loop.
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = [aws_subnet.private_backend.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ventas.arn
    container_name   = "ventas"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${local.name_prefix}-ventas" }
}

resource "aws_ecs_service" "despachos" {
  name            = "${local.name_prefix}-despachos"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.despachos.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = [aws_subnet.private_backend.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.despachos.arn
    container_name   = "despachos"
    container_port   = 8081
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${local.name_prefix}-despachos" }
}

resource "aws_ecs_service" "frontend" {
  name            = "${local.name_prefix}-frontend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = [aws_subnet.private_backend.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${local.name_prefix}-frontend" }
}

# =========================================================
# AUTOSCALING (IE3)
# =========================================================
locals {
  ecs_services = {
    ventas    = aws_ecs_service.ventas.name
    despachos = aws_ecs_service.despachos.name
    frontend  = aws_ecs_service.frontend.name
  }
}

resource "aws_appautoscaling_target" "ecs" {
  for_each           = local.ecs_services
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.this.name}/${each.value}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  for_each           = local.ecs_services
  name               = "${local.name_prefix}-${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 50.0
    scale_in_cooldown  = 60
    scale_out_cooldown = 60
  }
}
