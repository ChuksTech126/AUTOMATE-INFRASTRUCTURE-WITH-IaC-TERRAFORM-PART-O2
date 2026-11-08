# NETWORKING FUNDAMENTALS, THE OSI MODEL, TCP/IP SUITE AND AWS IAM POLICIES

## Introduction

Understanding networking, communication protocols, and identity management is essential when designing and managing cloud infrastructure.

These concepts explain how devices communicate, how data travels across networks, how applications deliver information to users, and how access to cloud resources is controlled.

This document covers three key areas:

1. Networking concepts: IP addresses, subnets, CIDR notation, IP routing, Internet Gateways, and NAT.
2. The OSI Model, TCP/IP suite, and their relationship to internet communication and end-to-end web solutions.
3. The difference between an IAM Assume Role Policy and a Role Permissions Policy.

---

# 1. UNDERSTANDING NETWORKING CONCEPTS

## 1.1 IP Address

An Internet Protocol (IP) address is a logical address assigned to a device or network interface to identify it and enable communication across an IP network.

It works similarly to a physical delivery address. Just as a delivery service needs an address to deliver a package, network devices need IP addresses to send and receive data.

There are two major versions of IP addresses:

- **IPv4:** Uses 32 bits and is commonly represented by four decimal numbers separated by dots. Example: `192.168.1.10`.
- **IPv6:** Uses 128 bits and is represented using hexadecimal values separated by colons. Example: `2001:db8::1`.

IP addresses can also be classified as:

- **Public IP address:** An address that is globally routable across the internet.
- **Private IP address:** An address used within private networks and not directly routable across the public internet.
- **Static IP address:** An address intended to remain unchanged.
- **Dynamic IP address:** An address assigned automatically and may change over time.

In AWS, EC2 instances within a VPC receive private IP addresses. Public-facing resources may also use public IP addresses or be accessed through public load balancers.

## 1.2 Subnets

A subnet is a logical division of a larger IP network into smaller networks.

Subnetting helps organize network resources, manage IP address allocation, and control communication between different parts of an infrastructure.

For example, consider a VPC with the CIDR block `172.16.0.0/16`.

It can be divided into smaller subnets:

```text
VPC:              172.16.0.0/16

Public Subnet 1:  172.16.0.0/24
Public Subnet 2:  172.16.1.0/24

Private Subnet 1: 172.16.2.0/24
Private Subnet 2: 172.16.3.0/24
```

Each subnet has its own IP address range. In AWS, each subnet is also associated with an Availability Zone.

**Importance of subnetting:**

- Organizes resources into separate network segments.
- Helps manage IP address allocation.
- Supports network security and access control.
- Separates internet-facing resources from private application and database resources.

For example, in a typical AWS architecture, public load balancers may be deployed in public subnets, while application servers and databases are deployed in private subnets.

## 1.3 CIDR Notation

Classless Inter-Domain Routing (CIDR) is a method of representing IP address ranges and identifying the network portion of an IP address.

For example:

```text
172.16.0.0/16
```

The `/16` indicates that the first 16 bits represent the network portion, while the remaining 16 bits are available for host addresses.

Another example:

```text
172.16.0.0/24
```

Here, 24 bits represent the network portion, leaving 8 bits for host addresses.

Some common CIDR ranges include:

| CIDR | Total IPv4 addresses |
|---|---:|
| /16 | 65,536 |
| /24 | 256 |
| /25 | 128 |
| /26 | 64 |

In AWS, five IPv4 addresses in every subnet are reserved, so the number of usable addresses is lower than the total.

**Terraform example:**

```hcl
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "172.16.0.0/24"
}
```

In this example, the VPC defines the larger network address space, while the subnet uses a smaller address range within that VPC.

## 1.4 IP Routing

IP routing is the process of determining where network traffic should be sent to reach its destination.

Routers use routing tables to identify the appropriate path for forwarding packets from one network to another.

A routing table generally contains:

- Destination network.
- Target or next hop.
- Routing information used to determine where traffic should go.

For example:

| Destination | Target |
|---|---|
| `172.16.0.0/16` | Local VPC |
| `0.0.0.0/0` | Internet Gateway |

The destination `0.0.0.0/0` represents the default IPv4 route. It is used when no more specific route matches the destination.

In AWS, route tables determine how traffic leaving a subnet is directed.

Routing is important because creating a VPC and subnets alone does not automatically provide internet connectivity. The appropriate routes and gateways must also be configured.

## 1.5 Internet Gateway (IGW)

An Internet Gateway is an AWS VPC component that enables communication between a VPC and the internet.

It is attached to a VPC, not directly to an individual subnet.

For resources in a public subnet to communicate directly with the internet, the following conditions must be satisfied:

1. An Internet Gateway must be attached to the VPC.
2. The subnet's associated route table must contain a route to the Internet Gateway, typically `0.0.0.0/0`.
3. The resource must have an appropriate public IP address.
4. Security groups and network ACLs must permit the intended traffic.

**Terraform example:**

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
```

The Internet Gateway provides the internet-routing path for appropriately configured public resources.

## 1.6 NAT Gateway

Network Address Translation (NAT) is a technique that allows private network resources to communicate with external networks by translating their network addresses.

In AWS, a NAT Gateway enables resources in private subnets to initiate outbound connections to the internet without allowing unsolicited internet connections to be initiated directly to those private resources.

For example, an EC2 instance in a private subnet may need to download software updates or install application packages.

It can send outbound traffic through a NAT Gateway.

In a typical AWS public NAT Gateway arrangement:

- The NAT Gateway is deployed in a public subnet.
- It is associated with an Elastic IP address.
- The public subnet routes internet-bound traffic through the Internet Gateway.
- The private subnet's route table directs its default route to the NAT Gateway.

**Terraform example:**

```hcl
resource "aws_route" "private_internet" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
```

### Difference Between Internet Gateway and NAT Gateway

| Internet Gateway | NAT Gateway |
|---|---|
| Provides internet connectivity for appropriately configured public resources. | Enables private resources to initiate outbound internet connections. |
| Attached to a VPC. | Deployed in a subnet. |
| Used as a target in public route tables. | Used as a target in private route tables. |
| Does not perform NAT for private instances. | Performs network address translation. |

### Application to AWS Infrastructure

These networking concepts work together when building an AWS environment.

- The VPC defines the overall IP address space.
- CIDR notation specifies the network ranges.
- Subnets divide the VPC into public and private segments.
- Route tables determine where network traffic is directed.
- The Internet Gateway provides internet routing for public resources.
- The NAT Gateway allows private resources to initiate outbound internet connections.

This demonstrates that creating network resources is only one part of networking. Routing and access configuration determine how the resources communicate.

---

# 2. THE OSI MODEL AND TCP/IP SUITE

## 2.1 Understanding the OSI Model

The Open Systems Interconnection (OSI) model is a conceptual framework used to explain how data moves from one device to another across a network.

It divides network communication into seven layers, with each layer responsible for a particular networking function.

The seven layers are:

| Layer | Name | Main Responsibility |
|---|---|---|
| 7 | Application | Provides network services to applications, such as web browsing and DNS. |
| 6 | Presentation | Handles data representation, formatting, encryption, and compression. |
| 5 | Session | Manages communication sessions between applications. |
| 4 | Transport | Handles end-to-end transport, ports, and delivery behaviour. |
| 3 | Network | Handles logical IP addressing and routing between networks. |
| 2 | Data Link | Handles communication across a local network using frames and MAC addresses. |
| 1 | Physical | Transmits raw bits through physical or wireless media. |

The most important thing about the OSI model is not memorising all seven layers. It is understanding that network communication involves different responsibilities.

For example:

- Applications need a way to request network services.
- Transport protocols manage communication between processes.
- IP addressing identifies source and destination networks.
- Routers forward packets between networks.
- Network technologies transmit the data.

The OSI model provides a structured way to understand these functions and troubleshoot networking problems.

## 2.2 Understanding the TCP/IP Suite

The TCP/IP suite, also known as the Internet Protocol Suite, is the collection of communication protocols that enables devices to communicate across the internet and other IP networks.

Unlike the OSI model, which is primarily a conceptual reference model, TCP/IP describes the protocols and architecture used in practical networking.

A commonly used representation of TCP/IP has four layers:

| TCP/IP Layer | Main Responsibility | Examples |
|---|---|---|
| Application | Provides network services to applications. | HTTP, HTTPS, DNS, SSH |
| Transport | Handles communication between processes and delivery behaviour. | TCP, UDP |
| Internet | Handles logical addressing and routing. | IP, ICMP |
| Network Access | Handles communication over the local network and physical medium. | Ethernet, Wi-Fi |

Some learning materials use a five-layer model by separating the Network Access layer into Data Link and Physical layers.

Both representations are used to explain TCP/IP networking.

## 2.3 Relationship Between the OSI Model and TCP/IP Suite

The OSI and TCP/IP models explain similar networking functions, but they organize those functions differently.

| OSI Model | TCP/IP Model |
|---|---|
| Application | Application |
| Presentation | Application |
| Session | Application |
| Transport | Transport |
| Network | Internet |
| Data Link | Network Access |
| Physical | Network Access |

The main relationship is:

- The OSI model provides a more detailed breakdown of networking responsibilities.
- The TCP/IP model groups those responsibilities into the architecture used by internet protocols.
- Both models help explain how data travels from one application to another across a network.

The OSI model is useful for understanding and troubleshooting networking concepts, while TCP/IP provides the practical protocol framework used by the internet.

## 2.4 How the Models Relate to the Internet and Web Applications

Consider a user accessing the following website:

```text
https://wordpress.chuksapp.com
```

For the webpage to load successfully, several networking processes must work together.

1. **Application:** The browser uses HTTPS to request the WordPress webpage. DNS resolves the hostname to an IP address.
2. **Transport:** TCP establishes a connection to the destination service. HTTPS commonly uses port 443.
3. **Internet:** IP addressing and routing move packets between the user's network and the AWS environment.
4. **Network Access:** Data is transmitted through the local network, Wi-Fi, Ethernet, or another network technology.
5. **Application delivery:** AWS services receive and process the request, eventually delivering the response from the web application.

In the AWS architecture, the request can follow this path:

```text
User's Browser
      |
      v
Amazon Route 53
      |
      v
External Application Load Balancer
      |
      v
NGINX Reverse Proxy
      |
      v
Internal Application Load Balancer
      |
      v
WordPress Web Server
      |
      v
MySQL Database
```

This illustrates how networking protocols and cloud services work together to deliver a web application.

The OSI and TCP/IP models explain the communication functions, while services such as Route 53, Application Load Balancers, NGINX, EC2, and MySQL participate in the actual application delivery process.

## 2.5 Encapsulation and Decapsulation

Two important concepts in layered network communication are encapsulation and decapsulation.

**Encapsulation** occurs when data moves down the networking layers at the sending device. Each layer adds information required for communication.

For example:

- The transport layer adds information such as source and destination port numbers.
- The internet layer adds source and destination IP addresses.
- The network access layer prepares the data for transmission across the local network.

**Decapsulation** occurs at the receiving device. The corresponding layers interpret and remove the protocol information as the data moves up the stack toward the receiving application.

This process allows devices and networks using different technologies to communicate with one another.

### Why This Understanding Matters

When a website fails to load, the problem may not necessarily be the application itself.

The issue could be related to:

- DNS resolution.
- Incorrect IP routing.
- A blocked port.
- A failed TCP connection.
- TLS or HTTPS configuration.
- A web server or application failure.

Understanding the networking layers provides a structured way to investigate and troubleshoot these problems.

**Key takeaway:** The OSI model explains the different responsibilities involved in network communication, while the TCP/IP suite provides the practical protocols that make internet communication possible.

---

# 3. DIFFERENCE BETWEEN ASSUME ROLE POLICY AND ROLE POLICY

AWS Identity and Access Management (IAM) provides a way to control who can access AWS resources and what actions they are permitted to perform.

When creating an IAM role, it is important to understand the difference between its trust policy and its permissions policy.

These policies answer two different questions:

1. Who is allowed to assume the role?
2. What is the role allowed to do after it has been assumed?

## 3.1 Assume Role Policy (Trust Policy)

An Assume Role Policy, also known as a Trust Policy, defines which AWS identities or services are trusted to assume an IAM role.

In simple terms, it answers:

**Who can use this role?**

For example, if an EC2 instance needs to assume an IAM role, the trust policy must allow the EC2 service to assume that role.

**Terraform example:**

```hcl
resource "aws_iam_role" "ec2_role" {
  name = "ec2-s3-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })
}
```

Understanding the important parts:

- `Effect = "Allow"`: Allows the specified action.
- `Principal`: Identifies the trusted identity or service. In this example, it is the EC2 service.
- `Action = "sts:AssumeRole"`: Allows the trusted principal to assume the role.

This policy does not give the EC2 instance permission to read or write S3 objects. It only establishes who is trusted to assume the role.

## 3.2 Role Policy (Permissions Policy)

A Role Policy defines the AWS actions that the role is permitted to perform after it has been assumed.

In simple terms, it answers:

**What can the role do?**

For example, if an EC2 instance needs permission to retrieve objects from an S3 bucket, a permissions policy can grant the role the required S3 permission.

**Terraform example:**

```hcl
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-read-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "s3:GetObject"
      ]

      Resource = "arn:aws:s3:::my-example-bucket/*"
    }]
  })
}
```

This policy grants the role permission to retrieve objects from the specified S3 bucket.

## 3.3 Comparison Between Assume Role Policy and Role Policy

| Assume Role Policy | Role Policy |
|---|---|
| Also called a Trust Policy. | Also called a Permissions Policy. |
| Defines who can assume the role. | Defines what the role can do. |
| Specifies a trusted principal. | Specifies permitted or denied actions and resources. |
| Uses role-assumption actions such as `sts:AssumeRole`. | Uses service actions such as `s3:GetObject` or `ec2:DescribeInstances`. |
| Attached as the role's trust policy. | Attached as an inline or managed permissions policy. |

## 3.4 How They Work Together

Imagine an EC2 instance needs to retrieve files from an S3 bucket.

The process works as follows:

1. The EC2 service is identified as a trusted principal in the role's trust policy.
2. EC2 assumes the IAM role through AWS Security Token Service (STS).
3. AWS provides temporary security credentials for the role session.
4. The role's permissions policy determines which S3 actions are allowed.
5. The EC2 instance can retrieve objects within the scope of the granted permissions.

The trust policy and permissions policy work together.

Trust alone does not grant access to S3, and S3 permissions alone do not establish who is allowed to assume the role.

## 3.5 Application to AWS Infrastructure

In an AWS infrastructure project, IAM roles can be used to provide permissions to EC2 instances and other AWS services.

This is different from using an IAM user and access keys for local programmatic access.

- **IAM User:** Represents an identity, such as a person or automation user, and can have long-term credentials.
- **IAM Role:** Provides temporary credentials to a trusted identity or service that assumes it.
- **Assume Role Policy:** Establishes who is trusted to assume the role.
- **Role Permissions Policy:** Determines what the role can access or perform.

IAM roles are particularly useful for EC2 instances that need to interact with other AWS services without embedding permanent access keys in application scripts.

